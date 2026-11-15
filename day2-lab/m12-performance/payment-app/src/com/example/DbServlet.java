package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class DbServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { String p=req.getParameter("hold"); long hold=p==null?0:Long.parseLong(p); javax.sql.DataSource ds=(javax.sql.DataSource)new javax.naming.InitialContext().lookup("java:comp/env/jdbc/paymentDB"); try (java.sql.Connection c=ds.getConnection(); java.sql.Statement st=c.createStatement(); java.sql.ResultSet r=st.executeQuery("SELECT count(*) FROM payments")) { r.next(); if (hold>0) Thread.sleep(hold); out.println("DB OK, payments="+r.getLong(1)); } } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
