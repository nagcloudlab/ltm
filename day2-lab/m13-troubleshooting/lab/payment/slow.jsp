<%@ page contentType="text/plain" trimDirectiveWhitespaces="true" %><%
 long ms = Long.parseLong(request.getParameter("ms") == null ? "1000" : request.getParameter("ms"));
 Thread.sleep(ms); %>Payment Service OK (slow <%= ms %> ms)
