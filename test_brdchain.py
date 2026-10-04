#!/usr/bin/env python3
"""Local end-to-end test for brdchain.py — no network, no real credentials.

Mock chain on the upstream side:
    client -> brdchain (SOCKS5) -> mock front proxy (CONNECT + auth)
           -> mock gateway (CONNECT + auth) -> echo

Verifies: SOCKS5 greeting, CONNECT request parsing, front hop CONNECT with
Proxy-Authorization, gateway CONNECT with Proxy-Authorization, byte piping.
"""

import random
import socket
import subprocess
import sys
import threading
import time

CHAIN = sys.argv[1] if len(sys.argv) > 1 else "brdchain.py"
FRONT_PORT = random.randint(20000, 30000)
CHAIN_PORT = random.randint(30001, 40000)

seen = {"front_auth": None, "gw_auth": None, "connects": 0}


def read_headers(sock):
    buf = b""
    while b"\r\n\r\n" not in buf:
        c = sock.recv(4096)
        if not c:
            raise OSError("closed")
        buf += c
    return buf.decode("latin-1")


def tunnel(sock, peer):
    try:
        while True:
            data = sock.recv(65536)
            if not data:
                break
            peer.sendall(data)
    except OSError:
        pass
    finally:
        for s in (sock, peer):
            try:
                s.close()
            except OSError:
                pass


def handle_front(sock):
    """Answers CONNECT, then becomes the gateway and answers a second CONNECT."""
    print("mock: connection accepted", flush=True)
    try:
        first = read_headers(sock)
        print("mock: first request =", repr(first), flush=True)
        assert first.startswith("CONNECT brd.superproxy.io:44445 "), first
        assert "Proxy-Authorization: Basic " in first, first
        seen["front_auth"] = [l for l in first.split("\r\n") if l.lower().startswith("proxy-auth")]
        sock.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")

        second = read_headers(sock)
        assert second.startswith("CONNECT brd.superproxy.io:44445 "), second
        assert "Proxy-Authorization: Basic " in second, second
        seen["gw_auth"] = [l for l in second.split("\r\n") if l.lower().startswith("proxy-auth")]
        seen["connects"] += 1
        sock.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")

        peer = socket.create_connection(("127.0.0.1", 19999))
        threading.Thread(target=tunnel, args=(sock, peer), daemon=True).start()
        tunnel(peer, sock)
    except Exception as exc:  # noqa: BLE001
        seen.setdefault("error", repr(exc))


def echo_server():
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 19999))
    srv.listen(16)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=tunnel, args=(c, c), daemon=True).start()


def mock_hub():
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", FRONT_PORT))
    srv.listen(16)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle_front, args=(c,), daemon=True).start()


def main():
    threading.Thread(target=echo_server, daemon=True).start()
    threading.Thread(target=mock_hub, daemon=True).start()
    time.sleep(0.3)

    proc = subprocess.Popen(
        [sys.executable, CHAIN,
         "--listen-port", str(CHAIN_PORT),
         "--target-host", "brd.superproxy.io", "--target-port", "44445",
         "--target-user", "brd-customer-hl_TEST-zone-isp_proxy1",
         "--target-pass", "s3cr3t",
         "--front-host", "127.0.0.1", "--front-port", str(FRONT_PORT),
         "--front-user", "frontuser", "--front-pass", "frontpass",
         "--auth-user", "relayuser", "--auth-pass", "relypass",
         "-v"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    time.sleep(1.2)

    # 1) client offering only "no auth" must be turned away
    try:
        a = socket.create_connection(("127.0.0.1", CHAIN_PORT), timeout=10)
        a.sendall(bytes([5, 1, 0]))
        noauth = a.recv(2)
        assert noauth[1] == 0xFF, f"expected 0xFF, got {noauth.hex()}"
        a.close()
    except Exception as exc:  # noqa: BLE001
        seen["error"] = repr(exc)
        echoed = b""

    # 2) wrong credentials must be rejected
    if not seen.get("error"):
        try:
            b_ = socket.create_connection(("127.0.0.1", CHAIN_PORT), timeout=10)
            b_.sendall(bytes([5, 2, 0, 2]))
            assert b_.recv(2)[1] == 0x02
            bad = b"wrong"
            b_.sendall(bytes([1, len(b"relayuser")]) + b"relayuser" + bytes([len(bad)]) + bad)
            assert b_.recv(2)[1] != 0x00, "relay accepted a wrong password"
            b_.close()
        except Exception as exc:  # noqa: BLE001
            seen["error"] = repr(exc)
            echoed = b""

    # 3) correct credentials get a working tunnel
    if not seen.get("error"):
        try:
            s = socket.create_connection(("127.0.0.1", CHAIN_PORT), timeout=10)
            s.sendall(bytes([5, 2, 0, 2]))
            assert s.recv(2)[1] == 0x02, "relay did not select userpass"
            u, pw = b"relayuser", b"relypass"
            s.sendall(bytes([1, len(u)]) + u + bytes([len(pw)]) + pw)
            assert s.recv(2)[1] == 0x00, "relay rejected the correct password"

            host = b"geo.brdtest.com"
            s.sendall(bytes([5, 1, 0, 3, len(host)]) + host + (443).to_bytes(2, "big"))
            head = s.recv(4)
            assert head[1] == 0, f"socks reply code {head[1]}"
            s.recv(6)
            s.sendall(b"PING-PAYLOAD-123")
            echoed = s.recv(4096)
            assert echoed == b"PING-PAYLOAD-123", echoed
            s.close()
        except Exception as exc:  # noqa: BLE001
            seen["error"] = repr(exc)
            echoed = b""

    time.sleep(0.4)
    proc.kill()
    proc.wait(timeout=10)
    chain_log = proc.stdout.read() if proc.stdout else ""

    print("--- brdchain log ---")
    print(chain_log.strip())
    print("--------------------")
    print("front hop auth  :", seen["front_auth"])
    print("gateway auth    :", seen["gw_auth"])
    print("gateway CONNECTs:", seen["connects"])
    print("echoed payload  :", echoed.decode())
    print("RESULT: PASS" if not seen.get("error") else f"RESULT: FAIL {seen['error']}")
    return 1 if seen.get("error") else 0


if __name__ == "__main__":
    sys.exit(main())