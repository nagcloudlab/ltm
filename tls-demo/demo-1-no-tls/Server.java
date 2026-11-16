import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

/**
 * Demo 1 server: plain HTTP, NO TLS, on port 9080.
 * POST /transfer  -> prints the request and answers "OK transfer accepted".
 * Everything on the wire (headers, token, PIN) is readable by anyone who captures the traffic.
 *
 * Run: java Server.java
 */
public class Server {

    public static void main(String[] args) throws Exception {
        int port = 9080;

        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/transfer", Server::transfer);
        server.start();
        System.out.println("HTTP server listening on http://localhost:" + port + "/transfer (no TLS)");
    }

    static void transfer(HttpExchange exchange) throws java.io.IOException {
        String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
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
