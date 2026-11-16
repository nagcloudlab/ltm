import java.io.FileInputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.KeyStore;

import javax.net.ssl.KeyManager;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManagerFactory;

/**
 * Demo 3 client: HTTPS with mutual TLS. Checks the server (as in demo 2) AND presents its own certificate.
 *
 * Run: java Client.java [keystore]
 *   keystore  default ../certs/client.p12
 *             "none" = connect without a client certificate
 */
public class Client {

    static final String URL = "https://localhost:9444/transfer";
    static final String BODY = "from=ACC-1001&to=ACC-1002&amount=5000&pin=4321";
    static final char[] PASSWORD = "changeit".toCharArray();

    public static void main(String[] args) throws Exception {
        String keystorePath = args.length > 0 ? args[0] : "../certs/client.p12";

        // 1. NEW: our own identity (client private key + certificate chain)
        KeyManager[] keyManagers = null;
        if (!keystorePath.equals("none")) {
            KeyStore keystore = KeyStore.getInstance("PKCS12");
            try (FileInputStream file = new FileInputStream(keystorePath)) {
                keystore.load(file, PASSWORD);
            }
            KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
            kmf.init(keystore, PASSWORD);
            keyManagers = kmf.getKeyManagers();
        }

        // 2. The CAs we trust for the SERVER certificate (same as demo 2)
        KeyStore truststore = KeyStore.getInstance("PKCS12");
        try (FileInputStream file = new FileInputStream("../certs/truststore.p12")) {
            truststore.load(file, PASSWORD);
        }
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(truststore);

        SSLContext tls = SSLContext.getInstance("TLS");
        tls.init(keyManagers, tmf.getTrustManagers(), null);

        HttpClient client = HttpClient.newBuilder().sslContext(tls).build();
        HttpRequest request = HttpRequest.newBuilder(URI.create(URL))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(BODY))
                .build();

        try {
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
            SSLSession session = response.sslSession().orElseThrow();
            System.out.println("TLS      " + session.getProtocol() + "  client certificate sent: "
                    + (session.getLocalCertificates() != null));
            System.out.println("SENT     POST " + URL + "  body=" + BODY);
            System.out.print("REPLY    " + response.statusCode() + " " + response.body());
        } catch (IOException e) {
            System.out.println("TLS FAILED  " + e.getClass().getSimpleName() + ": " + e.getMessage());
            System.exit(1);
        }
    }
}
