import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

/**
 * Demo 1 client: plain HTTP, NO TLS.
 * Sends one transfer (with a token and a PIN!) and prints the reply.
 *
 * Run: java Client.java [url]      (default http://localhost:9080/transfer)
 */
public class Client {

    static final String BODY = "from=ACC-1001&to=ACC-1002&amount=5000&pin=4321";
    static final String TOKEN = "Bearer secret-token-123";

    public static void main(String[] args) throws Exception {
        String url = args.length > 0 ? args[0] : "http://localhost:9080/transfer";

        HttpClient client = HttpClient.newHttpClient();
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .header("Authorization", TOKEN)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(BODY))
                .build();

        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
        System.out.println("SENT     POST " + url + "  body=" + BODY);
        System.out.print("REPLY    " + response.statusCode() + " " + response.body());
    }
}
