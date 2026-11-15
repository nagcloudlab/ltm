package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class StatusServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { out.println("Payment Service OK"); } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
