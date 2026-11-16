package com.example.notification;

import java.time.Duration;
import java.util.List;
import java.util.Properties;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.errors.WakeupException;
import org.apache.kafka.common.serialization.StringDeserializer;

/**
 * notification-service: a small Kafka consumer.
 *
 * Reads TransferCompleted events from the topic "transfers" (written by transfer-service)
 * and "sends" an SMS for each one (here: prints it).
 * It joins the consumer group "notification-service": start a second copy and
 * Kafka splits the partitions between the two copies.
 *
 * Usage: java -jar notification-service.jar      (stop with Ctrl+C)
 * Settings (environment variables):
 *   KAFKA_BOOTSTRAP  where Kafka listens   (default localhost:9092)
 *   TRANSFER_TOPIC   topic to read         (default transfers)
 *   GROUP_ID         consumer group        (default notification-service)
 */
public class NotificationService {

    public static void main(String[] args) {
        String bootstrap = env("KAFKA_BOOTSTRAP", "localhost:9092");
        String topic = env("TRANSFER_TOPIC", "transfers");
        String group = env("GROUP_ID", "notification-service");

        // 1. Consumer settings
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, group);
        props.put(ConsumerConfig.CLIENT_ID_CONFIG, "notification-service");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest"); // new group: start from the oldest event
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");   // we save our position ourselves

        KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);

        // 2. On Ctrl+C: wake the consumer up, wait for it to close cleanly
        Thread mainThread = Thread.currentThread();
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            consumer.wakeup();
            try {
                mainThread.join();
            } catch (InterruptedException ignored) {
            }
        }));

        System.out.printf("notification-service: reading topic '%s' on %s as group '%s' (Ctrl+C to stop)%n",
                topic, bootstrap, group);

        try {
            // 3. Join the group and subscribe to the topic
            consumer.subscribe(List.of(topic));
            while (true) {
                // 4. Ask Kafka for new events (wait up to 1 s)
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(1));
                for (ConsumerRecord<String, String> record : records) {
                    sendSms(record);
                    Thread.sleep(3); // tiny delay to simulate SMS sending
                }
                // 5. Save our position only after the SMS were sent
                if (!records.isEmpty()) {
                    consumer.commitSync();
                }
            }
        } 
        catch (InterruptedException e) {
            System.out.println("notification-service: interrupted");
        }
        catch (WakeupException e) {
            // normal stop after Ctrl+C
        } finally {
            consumer.close(); // leaves the group so the other copies take over at once
            System.out.println("notification-service: stopped");
        }
    }

    // "Send" an SMS: pick a few fields out of the JSON and print a message
    private static void sendSms(ConsumerRecord<String, String> record) {
        String json = record.value();
        System.out.printf("SMS      p%d/o%-4d to %s: Rs %s sent to %s (%s)%n",
                record.partition(), record.offset(),
                field(json, "from"), field(json, "amount"), field(json, "to"), field(json, "transferId"));
    }

    private static String field(String json, String name) {
        Matcher m = Pattern.compile("\"" + name + "\":\"?([^\",}]*)").matcher(json);
        return m.find() ? m.group(1) : "?";
    }

    private static String env(String name, String fallback) {
        String value = System.getenv(name);
        return (value == null || value.isBlank()) ? fallback : value;
    }
}
