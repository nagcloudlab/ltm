import java.io.FileInputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpsConfigurator;
import com.sun.net.httpserver.HttpsExchange;
import com.sun.net.httpserver.HttpsServer;

/**
 * Demo 2 server: HTTPS on port 9443 (the server proves who it is; the client stays anonymous).
 * Same /transfer endpoint as demo 1, now inside TLS.
 *
 * Run: java Server.java [keystore]    (default ../certs/server.p12)
 */
public class Server {

    static final char[] PASSWORD = "changeit".toCharArray();

    public static void main(String[] args) throws Exception {
        String keystorePath = args.length > 0 ? args[0] : "../certs/server.p12";
        int port = 9443;

        // 1. Load the server's identity: private key + certificate chain
        KeyStore keystore = KeyStore.getInstance("PKCS12");
        try (FileInputStream file = new FileInputStream(keystorePath)) {
            keystore.load(file, PASSWORD);
        }
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(keystore, PASSWORD);

        // 2. A TLS context that uses this identity (no trust store: clients are not checked in demo 2)
        SSLContext tls = SSLContext.getInstance("TLS");
        tls.init(kmf.getKeyManagers(), null, null);

        // 3. HttpsServer instead of HttpServer: the only other change from demo 1
        HttpsServer server = HttpsServer.create(new InetSocketAddress(port), 0);
        server.setHttpsConfigurator(new HttpsConfigurator(tls));
        server.createContext("/transfer", Server::transfer);
        server.start();
        System.out.println("HTTPS server listening on https://localhost:" + port + "/transfer with " + keystorePath);
    }

    static void transfer(HttpExchange exchange) throws java.io.IOException {
        SSLSession session = ((HttpsExchange) exchange).getSSLSession();
        String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
        System.out.println("TLS      " + session.getProtocol() + "  " + session.getCipherSuite());
        System.out.println("RECEIVED " + exchange.getRequestMethod() + " " + exchange.getRequestURI()
                + "  Authorization=" + exchange.getRequestHeaders().getFirst("Authorization")
                + "  body=" + body);

        byte[] reply = "OK transfer accepted\n".getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(200, reply.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(reply);
        }
    }
}
