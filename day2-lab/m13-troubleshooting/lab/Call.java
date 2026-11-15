import java.net.URI;
import java.net.http.*;
public class Call {
  public static void main(String[] a) throws Exception {
    HttpClient c = HttpClient.newHttpClient();
    HttpRequest r = HttpRequest.newBuilder(URI.create(a[0])).header("apikey","demo-key-123").build();
    System.out.println(c.send(r, HttpResponse.BodyHandlers.ofString()).body());
  }
}
