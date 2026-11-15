package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class NodeServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { out.println("served by Tomcat on port "+req.getLocalPort()); } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
