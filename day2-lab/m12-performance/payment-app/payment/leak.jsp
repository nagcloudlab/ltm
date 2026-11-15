<%@ page contentType="text/plain" import="javax.naming.*,javax.sql.*,java.sql.*" %><%
DataSource ds = (DataSource) new InitialContext().lookup("java:comp/env/jdbc/paymentDB");
Connection c = ds.getConnection(); /* never closed: a leak */
out.print("took a connection and never gave it back");
%>
