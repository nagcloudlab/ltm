package com.example.transfer;

import java.time.Instant;
import java.util.Properties;
import java.util.Random;
import java.util.UUID;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;

/**
 * transfer-service: a small Kafka producer.
 *
 * Every transfer between two bank accounts becomes one TransferCompleted event
 * on the Kafka topic "transfers".
 *   key   = the sender's account number (same account -> same partition -> kept in order)
 *   value = the transfer as one line of JSON
 *
 * Usage: java -jar transfer-service.jar [number-of-transfers] [delay-ms]
 * Settings (environment variables):
 *   KAFKA_BOOTSTRAP  where Kafka listens   (default localhost:9092)
 *   TRANSFER_TOPIC   topic to write to     (default transfers)
 */
public class TransferService {

    // Six accounts; on a 3-partition topic Kafka's key hashing puts two of them in each partition
    private static final String[] ACCOUNTS = {"ACC-1001", "ACC-1002", "ACC-1003", "ACC-1004", "ACC-1007", "ACC-1008"};

    public static void main(String[] args) throws Exception {
        int count = args.length > 0 ? Integer.parseInt(args[0]) : Integer.MAX_VALUE;
        long delayMs = args.length > 1 ? Long.parseLong(args[1]) : 1;
        String bootstrap = env("KAFKA_BOOTSTRAP", "localhost:9092");
        String topic = env("TRANSFER_TOPIC", "transfers");

        // 1. Producer settings
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        props.put(ProducerConfig.CLIENT_ID_CONFIG, "transfer-service");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, "all");                 // wait until Kafka has stored it
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");  // a retry never writes a duplicate
        props.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, "10000");        // wait up to 10 s to find the broker
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, "10000");  // wait up to 10 s for each answer
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, "30000"); // give up after 30 s in total

        System.out.printf("transfer-service: sending %d transfers to topic '%s' on %s%n", count, topic, bootstrap);

        Random random = new Random();
        // 2. Open the producer; try-with-resources flushes and closes it at the end
        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            for (int i = 1; i <= count; i++) {
                // 3. Build one transfer event
                String from = ACCOUNTS[random.nextInt(ACCOUNTS.length)];
                String to;
                do {
                    to = ACCOUNTS[random.nextInt(ACCOUNTS.length)];
                } while (to.equals(from));
                int amount = 100 * (1 + random.nextInt(50));
                String transferId = "TRF-" + UUID.randomUUID().toString().substring(0, 8);

                String json = String.format(
                        "{\"event\":\"TransferCompleted\",\"transferId\":\"%s\",\"from\":\"%s\",\"to\":\"%s\","
                                + "\"amount\":%d,\"currency\":\"INR\",\"time\":\"%s\"}",
                        transferId, from, to, amount, Instant.now());

                // 4. Send it; Kafka answers later with partition and offset (or an error)
                ProducerRecord<String, String> record = new ProducerRecord<>(topic, from, json);
                producer.send(record, (meta, error) -> {
                    if (error != null) {
                        System.out.printf("FAILED   %s key=%s : %s%n", transferId, from, error.getMessage());
                    } else {
                        System.out.printf("SENT     %s key=%s partition=%d offset=%d%n",
                                transferId, from, meta.partition(), meta.offset());
                    }
                });

                if (delayMs > 0 && i < count) {
                    Thread.sleep(delayMs);
                }
            }
        }
        System.out.println("transfer-service: done");
    }

    private static String env(String name, String fallback) {
        String value = System.getenv(name);
        return (value == null || value.isBlank()) ? fallback : value;
    }
}
