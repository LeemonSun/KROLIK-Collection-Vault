#!/usr/bin/env python3
"""Independent local HTTPS fixture; keys live only in a temporary directory."""
import http.server, os, ssl, subprocess, sys, tempfile, threading
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
    requests=[]
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args): pass
        def do_GET(self):
            requests.append((self.path,dict(self.headers)))
            if self.path=='/redirect':
                self.send_response(302);self.send_header('Location','http://127.0.0.1/private');self.send_header('Content-Length','0');self.end_headers();return
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8')
            if self.path=='/large':
                self.send_header('Content-Length',str(262145));self.end_headers();self.close_connection=True;return
            if self.path=='/chunked':
                self.send_header('Transfer-Encoding','chunked');self.end_headers()
                for block in [b'<p>first ',b'second</p>']:
                    self.wfile.write(f'{len(block):X}\r\n'.encode()+block+b'\r\n');self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n');self.wfile.flush();return
            body='<html><head><title>not body</title></head><body><script>do not execute</script><p>Документ &amp; 中文</p></body></html>'.encode()
            self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    with tempfile.TemporaryDirectory(prefix='leemon-local-tls-') as folder:
        folder=Path(folder);cert=folder/'certificate.pem';key=folder/'private.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=public.example.com','-addext','subjectAltName=DNS:public.example.com'],check=True,capture_output=True)
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.load_cert_chain(cert,key);server.socket=tls.wrap_socket(server.socket,server_side=True)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        pack=os.environ.get('LEEMON_TEST_PACK');command=[sys.argv[1],'--headless','--path',str(Path(pack).parent if pack else ROOT)]
        if pack:command+=['--main-pack',pack]
        command+=['--script',str(ROOT/'tests/test_public_tls014.gd') if pack else 'res://tests/test_public_tls014.gd','--','--test-mode']
        try:
            result=subprocess.run(command,env=dict(os.environ,LEEMON_TEST_CA=str(cert),LEEMON_TEST_TLS_PORT=str(server.server_port),XDG_DATA_HOME=str(folder/'profile'),XDG_CONFIG_HOME=str(folder/'profile')),capture_output=True,text=True,timeout=40)
        finally:server.shutdown();server.server_close();thread.join(timeout=2)
        log=result.stdout+result.stderr;print(log)
        if result.returncode or 'SCRIPT ERROR:' in log or '\nERROR:' in log:return 1
        assert [x[0] for x in requests]==['/good','/chunked','/redirect','/large'],requests
        assert all(h.get('Host')=='public.example.com' and 'Cookie' not in h and 'Authorization' not in h for _,h in requests)
        print('INDEPENDENT_HTTPS_REQUESTS: PASS; expected paths/Host, no credentials, no redirected request, private key removed')
    return 0
if __name__=='__main__':raise SystemExit(main())
