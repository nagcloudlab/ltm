<%@ page contentType="text/plain" %>remoteAddr=<%= request.getRemoteAddr() %> scheme=<%= request.getScheme() %> host=<%= request.getServerName() %>
X-Forwarded-For=<%= request.getHeader("X-Forwarded-For") %>
X-Forwarded-Proto=<%= request.getHeader("X-Forwarded-Proto") %>
