package lab;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.*;
import java.io.IOException;
public class PaymentServlet extends HttpServlet {
    @Override protected void doGet(HttpServletRequest req, HttpServletResponse res)
            throws ServletException, IOException {
        String path = req.getPathInfo();
        if (path == null) path = "/";
        res.setCharacterEncoding("UTF-8");
        res.setHeader("X-Payment-Release", "1.0");
        res.setHeader("Cache-Control", "no-store");
        if (path.equals("/fail")) {
            getServletContext().log("LAB simulated payment failure");
            throw new ServletException("LAB simulated payment failure; hand stack trace to developers");
        }
        if (path.equals("/slow")) {
            int delay = 15000;
            try { if (req.getParameter("ms") != null) delay = Integer.parseInt(req.getParameter("ms")); }
            catch (NumberFormatException e) { res.sendError(400, "ms must be an integer"); return; }
            if (delay < 0 || delay > 20000) { res.sendError(400, "ms must be 0..20000"); return; }
            try { Thread.sleep(delay); } catch (InterruptedException e) {
                Thread.currentThread().interrupt(); res.sendError(503); return;
            }
            res.setContentType("text/plain"); res.getWriter().println("Payment response after " + delay + " ms"); return;
        }
        if (path.equals("/balance")) {
            res.setContentType("application/json");
            res.getWriter().println("{\"account\":\"1234\",\"balance\":42500,\"currency\":\"INR\",\"demo\":true}"); return;
        }
        if (path.equals("/status")) {
            res.setContentType("text/plain"); res.getWriter().println("Payment Service OK"); return;
        }
        res.sendError(404, "Unknown payment endpoint");
    }
}
