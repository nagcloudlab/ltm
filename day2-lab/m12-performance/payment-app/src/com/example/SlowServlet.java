package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class SlowServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { String p=req.getParameter("ms"); long ms=p==null?1000:Long.parseLong(p); Thread.sleep(ms); out.println("Payment Service OK (waited "+ms+" ms)"); } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
