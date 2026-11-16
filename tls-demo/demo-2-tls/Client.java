import java.io.FileInputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManagerFactory;

/**
 * Demo 2 client: HTTPS. Checks the server's certificate, then sends the same transfer as demo 1.
 *
 * Run: java Client.java [url] [truststore]
 *   url         default https://localhost:9443/transfer
 *   truststore  default ../certs/truststore.p12
 *               "java-default" = Java's built-in list of public CAs (cacerts)
 */
public class Client {

    static final String BODY = "from=ACC-1001&to=ACC-1002&amount=5000&pin=4321";
    static final String TOKEN = "Bearer secret-token-123";
    static final char[] PASSWORD = "changeit".toCharArray();

    public static void main(String[] args) throws Exception {
        String url = args.length > 0 ? args[0] : "https://localhost:9443/transfer";
        String truststorePath = args.length > 1 ? args[1] : "../certs/truststore.p12";

        // 1. Decide which CAs we trust
        SSLContext tls;
        if (truststorePath.equals("java-default")) {
            tls = SSLContext.getDefault();                  // only the public CAs shipped with Java
        } else {
            KeyStore truststore = KeyStore.getInstance("PKCS12");
            try (FileInputStream file = new FileInputStream(truststorePath)) {
                truststore.load(file, PASSWORD);
            }
            TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            tmf.init(truststore);
            tls = SSLContext.getInstance("TLS");
            tls.init(null, tmf.getTrustManagers(), null);
        }

        // 2. An HTTPS client with that trust. It also checks that the certificate matches the host name in the URL.
        HttpClient client = HttpClient.newBuilder().sslContext(tls).build();
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .header("Authorization", TOKEN)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(BODY))
                .build();

        try {
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            // 3. What did the TLS handshake agree on, and which certificates did the server send?
            SSLSession session = response.sslSession().orElseThrow();
            System.out.println("TLS      " + session.getProtocol() + "  " + session.getCipherSuite());
            Certificate[] chain = session.getPeerCertificates();
            for (int i = 0; i < chain.length; i++) {
                X509Certificate cert = (X509Certificate) chain[i];
                System.out.println("  server chain [" + i + "] " + cert.getSubjectX500Principal().getName()
                        + "  (issuer: " + cert.getIssuerX500Principal().getName() + ")");
            }
            System.out.println("SENT     POST " + url + "  body=" + BODY);
            System.out.print("REPLY    " + response.statusCode() + " " + response.body());
        } catch (IOException e) {
            System.out.println("TLS FAILED  " + e.getClass().getSimpleName() + ": " + e.getMessage());
            System.exit(1);
        }
    }
}
