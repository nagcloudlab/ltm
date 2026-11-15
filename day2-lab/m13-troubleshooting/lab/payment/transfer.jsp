<%@ page contentType="application/json" trimDirectiveWhitespaces="true" import="java.net.*,java.io.*,java.util.*" %><%
 String rid = request.getHeader("X-Request-ID");
 String id = "TX" + (100000 + new Random().nextInt(900000));
 String to = request.getParameter("to"); if (to == null) to = "+919800000001";
 String amt = request.getParameter("amount"); if (amt == null) amt = "500";
 String evt = "{\\\"event\\\":\\\"PaymentCompleted\\\",\\\"transferId\\\":\\\"" + id + "\\\",\\\"amount\\\":" + amt + ",\\\"phone\\\":\\\"" + to + "\\\",\\\"requestId\\\":\\\"" + rid + "\\\"}";
 String body = "{\"properties\":{\"delivery_mode\":2,\"headers\":{\"x-request-id\":\"" + rid + "\"}},\"routing_key\":\"payment.completed\",\"payload\":\"" + evt + "\",\"payload_encoding\":\"string\"}";
 HttpURLConnection c = (HttpURLConnection) new URL("http://127.0.0.1:15672/api/exchanges/%2F/payments/publish").openConnection();
 c.setRequestMethod("POST"); c.setDoOutput(true);
 c.setRequestProperty("Authorization", "Basic " + Base64.getEncoder().encodeToString("guest:guest".getBytes()));
 c.setRequestProperty("Content-Type", "application/json");
 c.getOutputStream().write(body.getBytes("UTF-8"));
 int rc = c.getResponseCode();
 application.log("transfer " + id + " published PaymentCompleted requestId=" + rid + " broker=" + rc);
 response.setStatus(202); %>{"status":"ACCEPTED","transferId":"<%= id %>"}
