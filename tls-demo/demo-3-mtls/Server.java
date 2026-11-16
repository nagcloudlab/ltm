import java.io.FileInputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.cert.X509Certificate;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManagerFactory;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsExchange;
import com.sun.net.httpserver.HttpsParameters;
import com.sun.net.httpserver.HttpsServer;

/**
 * Demo 3 server: HTTPS with mutual TLS (mTLS) on port 9444.
 * The server proves who it is AND demands a client certificate.
 *   Authentication: the client certificate must chain to a CA in our trust store (done by TLS).
 *   Authorization:  the client's name (CN) must be on our allow list (done by this code).
 *
 * Run: java Server.java
 */
public class Server {

    static final char[] PASSWORD = "changeit".toCharArray();
    static final Set<String> ALLOWED_CLIENTS = Set.of("transfer-client");

    public static void main(String[] args) throws Exception {
        int port = 9444;

        // 1. Our identity (same server certificate as demo 2)
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(load("../certs/server.p12"), PASSWORD);

        // 2. NEW: the CAs we accept CLIENT certificates from
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(load("../certs/truststore.p12"));

        SSLContext tls = SSLContext.getInstance("TLS");
        tls.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);

        HttpsServer server = HttpsServer.create(new InetSocketAddress(port), 0);
        server.setHttpsConfigurator(new HttpsConfigurator(tls) {
            @Override
            public void configure(HttpsParameters params) {
                // 3. NEW: a client without a valid certificate is refused during the handshake
                SSLParameters sslParams = getSSLContext().getDefaultSSLParameters();
                sslParams.setNeedClientAuth(true);
                params.setSSLParameters(sslParams);
            }
        });
        server.createContext("/transfer", Server::transfer);
        server.start();
        System.out.println("mTLS server listening on https://localhost:" + port + "/transfer (client certificate required)");
    }

    static void transfer(HttpExchange exchange) throws java.io.IOException {
        SSLSession session = ((HttpsExchange) exchange).getSSLSession();

        // 4. Who is the client? Read the name from its certificate
        X509Certificate clientCert = (X509Certificate) session.getPeerCertificates()[0];
        String clientCn = commonName(clientCert);
        String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        System.out.println("TLS      " + session.getProtocol() + "  client certificate CN=" + clientCn
                + "  (issuer: " + clientCert.getIssuerX500Principal().getName() + ")");

        // 5. Authorization: a valid certificate is not enough, the name must be allowed
        int status;
        String reply;
        if (ALLOWED_CLIENTS.contains(clientCn)) {
            System.out.println("RECEIVED POST /transfer  body=" + body);
            status = 200;
            reply = "OK transfer accepted for " + clientCn + "\n";
        } else {
            System.out.println("REJECTED " + clientCn + " is not on the allow list");
            status = 403;
            reply = "FORBIDDEN " + clientCn + " may not make transfers\n";
        }

        byte[] bytes = reply.getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    static KeyStore load(String path) throws Exception {
        KeyStore store = KeyStore.getInstance("PKCS12");
        try (FileInputStream file = new FileInputStream(path)) {
            store.load(file, PASSWORD);
        }
        return store;
    }

    static String commonName(X509Certificate cert) {
        Matcher m = Pattern.compile("CN=([^,]+)").matcher(cert.getSubjectX500Principal().getName());
        return m.find() ? m.group(1) : "?";
    }
}
