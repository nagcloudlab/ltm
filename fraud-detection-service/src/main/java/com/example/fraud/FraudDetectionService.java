package com.example.fraud;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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
 * fraud-detection-service: a second Kafka consumer of the same "transfers" topic.
 *
 * It uses its OWN consumer group ("fraud-detection-service"), so it receives EVERY event,
 * independently of notification-service. Two simple rules:
 *   HIGH_AMOUNT  one transfer of Rs 4000 or more
 *   VELOCITY     more than 5 transfers from the same account within 10 seconds
 * VELOCITY keeps a small history per account. That only works because the event key is the
 * account number: all events of one account land in one partition, so one consumer sees them all.
 *
 * Usage: java -jar fraud-detection-service.jar      (stop with Ctrl+C)
 * Settings (environment variables):
 *   KAFKA_BOOTSTRAP  where Kafka listens   (default localhost:9092)
 *   TRANSFER_TOPIC   topic to read         (default transfers)
 *   GROUP_ID         consumer group        (default fraud-detection-service)
 */
public class FraudDetectionService {

    static final int HIGH_AMOUNT = 4000;                          // Rs
    static final int VELOCITY_MAX = 5;                            // transfers allowed ...
    static final Duration VELOCITY_WINDOW = Duration.ofSeconds(10); // ... within this time

    // Per account: times of its recent transfers, and when we last raised a VELOCITY alert
    static final Map<String, Deque<Instant>> recent = new HashMap<>();
    static final Map<String, Instant> lastVelocityAlert = new HashMap<>();

    static long checked = 0;
    static long alerts = 0;

    public static void main(String[] args) {
        String bootstrap = env("KAFKA_BOOTSTRAP", "localhost:9092");
        String topic = env("TRANSFER_TOPIC", "transfers");
        String group = env("GROUP_ID", "fraud-detection-service");

        // 1. Consumer settings: same as notification-service, but a different group
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, group);
        props.put(ConsumerConfig.CLIENT_ID_CONFIG, "fraud-detection-service");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest"); // new group: check every event from the start
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");   // commit only after checking

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

        System.out.printf("fraud-detection-service: reading topic '%s' on %s as group '%s' (Ctrl+C to stop)%n",
                topic, bootstrap, group);
        System.out.printf("rules: HIGH_AMOUNT >= Rs %d, VELOCITY > %d transfers per account in %d s%n",
                HIGH_AMOUNT, VELOCITY_MAX, VELOCITY_WINDOW.toSeconds());

        long nextSummary = System.currentTimeMillis() + 5000;
        try {
            consumer.subscribe(List.of(topic));
            while (true) {
                // 3. Fetch new events and check each one
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofSeconds(1));
                for (ConsumerRecord<String, String> record : records) {
                    check(record);
                }
                // 4. Commit only after the events were checked
                if (!records.isEmpty()) {
                    consumer.commitSync();
                }
                // 5. A short summary every 5 seconds, so the screen is not flooded
                if (System.currentTimeMillis() >= nextSummary) {
                    System.out.printf("SUMMARY  checked=%d alerts=%d%n", checked, alerts);
                    nextSummary = System.currentTimeMillis() + 5000;
                }
            }
        } catch (WakeupException e) {
            // normal stop after Ctrl+C
        } finally {
            consumer.close();
            System.out.printf("fraud-detection-service: stopped (checked=%d alerts=%d)%n", checked, alerts);
        }
    }

    // Apply both rules to one transfer event
    static void check(ConsumerRecord<String, String> record) {
        String json = record.value();
        String account = record.key();
        int amount = Integer.parseInt(field(json, "amount"));
        Instant time = Instant.parse(field(json, "time"));   // event time, not "now": a replay gives the same result
        String where = String.format("p%d/o%-5d", record.partition(), record.offset());
        checked++;

        // Rule 1: one large transfer
        if (amount >= HIGH_AMOUNT) {
            alert("HIGH_AMOUNT", where, account, "Rs " + amount + " to " + field(json, "to")
                    + " (" + field(json, "transferId") + ")");
        }

        // Rule 2: too many transfers from one account in a short time
        Deque<Instant> times = recent.computeIfAbsent(account, a -> new ArrayDeque<>());
        times.addLast(time);
        while (!times.isEmpty() && times.peekFirst().isBefore(time.minus(VELOCITY_WINDOW))) {
            times.removeFirst();                              // forget transfers older than the window
        }
        Instant last = lastVelocityAlert.get(account);
        boolean alertedInWindow = last != null && last.isAfter(time.minus(VELOCITY_WINDOW));
        if (times.size() > VELOCITY_MAX && !alertedInWindow) {  // alert once per window, not for every event
            alert("VELOCITY", where, account, times.size() + " transfers in " + VELOCITY_WINDOW.toSeconds() + " s");
            lastVelocityAlert.put(account, time);
        }
    }

    static void alert(String rule, String where, String account, String detail) {
        alerts++;
        System.out.printf("ALERT    %-11s %s %s: %s%n", rule, where, account, detail);
    }

    static String field(String json, String name) {
        Matcher m = Pattern.compile("\"" + name + "\":\"?([^\",}]*)").matcher(json);
        return m.find() ? m.group(1) : "?";
    }

    static String env(String name, String fallback) {
        String value = System.getenv(name);
        return (value == null || value.isBlank()) ? fallback : value;
    }
}
