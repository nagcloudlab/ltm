// TlsCheck.java - call an HTTPS URL from Java and print the status and body.
// Java uses its OWN trust store (cacerts), not curl's.
// run: java TlsCheck.java https://portal.example.test/health.txt
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

public class TlsCheck {
    public static void main(String[] args) throws Exception {
        HttpResponse<String> r = HttpClient.newHttpClient().send(
            HttpRequest.newBuilder(URI.create(args[0])).build(),
            HttpResponse.BodyHandlers.ofString());
        System.out.println(r.statusCode() + " " + r.body().trim());
    }
}
