package com.example;
import jakarta.servlet.http.*; import java.io.*;
public class SessionServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse res) throws IOException {
    res.setContentType("text/plain"); PrintWriter out = res.getWriter();
    try { HttpSession s=req.getSession(); Integer n=(Integer)s.getAttribute("n"); n=n==null?1:n+1; s.setAttribute("n",n); out.println("port="+req.getLocalPort()+" session="+s.getId()+" visits="+n+" timeout="+s.getMaxInactiveInterval()+"s"); } catch (RuntimeException e) { throw e; } catch (Exception e) { throw new RuntimeException(e); }
  }
}
