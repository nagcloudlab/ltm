package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class LeakServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { javax.sql.DataSource ds=(javax.sql.DataSource)new javax.naming.InitialContext().lookup("java:comp/env/jdbc/paymentDB"); java.sql.Connection c=ds.getConnection(); out.println("took a connection, never gave it back"); } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
