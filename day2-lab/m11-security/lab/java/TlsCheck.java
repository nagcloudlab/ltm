import java.net.URI;
import java.net.http.*;
public class TlsCheck {
    public static void main(String[] a) throws Exception {
        var r = HttpClient.newHttpClient().send(
            HttpRequest.newBuilder(URI.create(a[0])).build(),
            HttpResponse.BodyHandlers.ofString());
        System.out.println(r.statusCode() + " " + r.body());
    }
}
