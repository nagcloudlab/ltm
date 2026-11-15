package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class WhoamiServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { out.println("remoteAddr="+req.getRemoteAddr()+"  scheme="+req.getScheme()+"  secure="+req.isSecure()); out.println("X-Forwarded-For="+req.getHeader("X-Forwarded-For")); out.println("X-Forwarded-Proto="+req.getHeader("X-Forwarded-Proto")); } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
