#!/usr/bin/env python3
import sys
import socket
import select
import threading

def parse_http_request(data):
    lines = data.split(b"\r\n")
    if not lines:
        return None, None, None
    parts = lines[0].split(b" ")
    if len(parts) < 2:
        return None, None, None
    method = parts[0].decode('latin1', errors='ignore')
    target = parts[1].decode('latin1', errors='ignore')
    return method, target, lines

def connect_socks5(socks_host, socks_port, target_host, target_port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((socks_host, socks_port))
    s.sendall(b"\x05\x01\x00")
    resp = s.recv(2)
    if len(resp) < 2 or resp[0] != 5 or resp[1] != 0:
        s.close()
        raise Exception("SOCKS5 handshake failed")
    host_bytes = target_host.encode('utf-8')
    req = b"\x05\x01\x00\x03" + bytes([len(host_bytes)]) + host_bytes + target_port.to_bytes(2, 'big')
    s.sendall(req)
    resp = s.recv(4)
    if len(resp) < 4 or resp[1] != 0:
        s.close()
        raise Exception(f"SOCKS5 connection to {target_host}:{target_port} failed")
    atyp = resp[3]
    if atyp == 1:
        s.recv(6)
    elif atyp == 3:
        n = s.recv(1)[0]
        s.recv(n + 2)
    elif atyp == 4:
        s.recv(18)
    return s

def pipe(src, dst):
    try:
        while True:
            data = src.recv(8192)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            src.close()
        except Exception:
            pass
        try:
            dst.close()
        except Exception:
            pass

def handle_client(client_sock, socks_host, socks_port):
    try:
        first_chunk = client_sock.recv(8192)
        if not first_chunk:
            client_sock.close()
            return

        method, target, lines = parse_http_request(first_chunk)
        if not method or not target:
            client_sock.close()
            return

        if method.upper() == 'CONNECT':
            if ':' in target:
                host, port_str = target.split(':', 1)
                port = int(port_str)
            else:
                host = target
                port = 443
            remote_sock = connect_socks5(socks_host, socks_port, host, port)
            client_sock.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            t1 = threading.Thread(target=pipe, args=(client_sock, remote_sock))
            t2 = threading.Thread(target=pipe, args=(remote_sock, client_sock))
            t1.daemon = True
            t2.daemon = True
            t1.start()
            t2.start()
        else:
            url = target
            host = None
            port = 80
            if url.startswith("http://"):
                url_wo_scheme = url[7:]
                slash_idx = url_wo_scheme.find("/")
                host_part = url_wo_scheme if slash_idx == -1 else url_wo_scheme[:slash_idx]
                if ":" in host_part:
                    host, port_str = host_part.split(":", 1)
                    port = int(port_str)
                else:
                    host = host_part
            if not host:
                for line in lines[1:]:
                    if line.lower().startswith(b"host:"):
                        h = line[5:].strip().decode('latin1', errors='ignore')
                        if ":" in h:
                            host, port_str = h.split(":", 1)
                            port = int(port_str)
                        else:
                            host = h
                        break
            if not host:
                client_sock.close()
                return

            remote_sock = connect_socks5(socks_host, socks_port, host, port)
            remote_sock.sendall(first_chunk)
            t1 = threading.Thread(target=pipe, args=(client_sock, remote_sock))
            t2 = threading.Thread(target=pipe, args=(remote_sock, client_sock))
            t1.daemon = True
            t2.daemon = True
            t1.start()
            t2.start()
    except Exception:
        try:
            client_sock.close()
        except Exception:
            pass

def main():
    if len(sys.argv) < 4:
        print("Usage: socks2http_bridge.py <http_listen_port> <socks_host> <socks_port> [listen_host]")
        sys.exit(1)

    listen_port = int(sys.argv[1])
    socks_host = sys.argv[2]
    socks_port = int(sys.argv[3])
    listen_host = sys.argv[4] if len(sys.argv) > 4 else '127.0.0.1'

    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind((listen_host, listen_port))
    server_sock.listen(128)
    print(f"READY {listen_port}", flush=True)

    while True:
        try:
            client, _ = server_sock.accept()
            t = threading.Thread(target=handle_client, args=(client, socks_host, socks_port))
            t.daemon = True
            t.start()
        except KeyboardInterrupt:
            break
        except Exception:
            break

if __name__ == '__main__':
    main()
