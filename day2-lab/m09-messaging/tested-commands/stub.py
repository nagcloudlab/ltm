import http.server, time, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        b=json.dumps({"paymentId":"PAY-1001","status":"queued"}).encode()
        self.send_response(202); self.send_header('Content-Type','application/json'); self.send_header('Location','/payment/status/PAY-1001'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_HEAD(self):
        time.sleep(12); self.send_response(200); self.end_headers()
    do_GET=do_HEAD
http.server.ThreadingHTTPServer(('127.0.0.1',8080),H).serve_forever()
