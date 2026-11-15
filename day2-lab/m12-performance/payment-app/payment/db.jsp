<%@ page contentType="text/plain" import="javax.naming.*,javax.sql.*,java.sql.*" %><%
long hold = Long.parseLong(request.getParameter("hold") == null ? "0" : request.getParameter("hold"));
DataSource ds = (DataSource) new InitialContext().lookup("java:comp/env/jdbc/paymentDB");
try (Connection c = ds.getConnection(); Statement s = c.createStatement(); ResultSet r = s.executeQuery("SELECT count(*) FROM payments")) {
  r.next(); out.print("DB OK, payments=" + r.getLong(1));
  if (hold > 0) Thread.sleep(hold);
}
%>
