#!/usr/bin/env python3
"""
brdchain.py — SOCKS5 relay that chains to a Bright Data ISP zone through a
front hop, so the zone sees an allowed source IP instead of yours.

    ShardX / curl / anything
        -> socks5://RELAY:1080              (this script, auth optional)
        -> FRONT proxy                       (HTTP CONNECT, its own creds)
        -> brd.superproxy.io:44445           (HTTP gateway, Basic auth)
        -> destination

Why: Bright Data ISP zones enforce an ACL on the *source* address and answer
with `HTTP/1.1 401 Auth Failed (code: ip_blacklisted)` / `client_10050` when it
does not like where you are coming from. No client-side setting changes that —
the only fix is to reach the gateway from an address the zone accepts. This
process is that second address, and it stays up independently of your laptop,
which is why it is worth deploying on a small cloud VM.

Target: Linux (amd64/arm64), macOS, anywhere with Python 3.9+. Zero deps.

Quick start
    export BRD_USER='brd-customer-hl_XXXX-zone-isp_proxy1'
    export BRD_PASS='...'
    export RELAY_USER='pick-something-long'
    export RELAY_PASS='...'
    python3 brdchain.py --listen-host 0.0.0.0 --front-host H --front-port P

Self-test
    python3 brdchain.py --check    # one real request through the whole chain

Client
    curl --socks5-hostname RELAY:1080 --proxy-user "$RELAY_USER:$RELAY_PASS" \
         https://geo.brdtest.com/welcome.txt?product=isp&method=native

Notes
    * CONNECT only, no UDP_ASSOCIATE. Clients that need QUIC or WebRTC UDP will
      fall back to TCP; do not expose this as a general-purpose proxy.
    * Credentials belong in the environment or /etc/brdchain.env, never in git.
"""

import argparse
import base64
import hmac
import os
import selectors
import socket
import ssl
import sys
import threading

SOCKS_VER = 0x05
CMD_CONNECT = 0x01
CMD_UDP_ASSOCIATE = 0x03

METHOD_NO_AUTH = 0x00
METHOD_USERPASS = 0x02
METHOD_NONE_ACCEPTABLE = 0xFF

ATYP_IPV4 = 0x01
ATYP_DOMAIN = 0x03
ATYP_IPV6 = 0x04

REPLY_OK = 0x00
REPLY_GENERAL_FAILURE = 0x01
REPLY_CMD_NOT_SUPPORTED = 0x07


def log(*parts):
    if VERBOSE:
        sys.stderr.write("[brdchain] " + " ".join(str(p) for p in parts) + "\n")
        sys.stderr.flush()


VERBOSE = False


def basic_auth(user, password):
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    return f"Proxy-Authorization: Basic {token}"


def recv_headers(sock, limit=65536):
    """Read up to and including the first blank line. Returns bytes or None."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        try:
            chunk = sock.recv(4096)
        except OSError:
            return None
        if not chunk:
            return None
        buf += chunk
        if len(buf) > limit:
            return None
    return buf


def send_socks_reply(sock, code, addr=b"\x00\x00\x00\x00", port=0):
    sock.sendall(bytes([SOCKS_VER, code, 0x00]) + addr + port.to_bytes(2, "big"))


def read_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise OSError("connection closed while reading %d bytes" % n)
        buf += chunk
    return buf


def parse_greeting(sock, required):
    """ver, nmethods, methods -> the method we require, or None if unusable."""
    header = read_exact(sock, 2)
    if header[0] != SOCKS_VER:
        raise OSError("not a SOCKS5 client (ver=0x%02x)" % header[0])
    nmethods = header[1]
    methods = set(read_exact(sock, nmethods))
    if required in methods:
        return required
    return None


def parse_userpass(sock):
    """RFC 1929: ver, ulen, uname, plen, passwd -> (user, password)."""
    header = read_exact(sock, 2)
    if header[0] != 0x01:
        raise OSError("bad userpass auth version 0x%02x" % header[0])
    user = read_exact(sock, header[1]).decode("utf-8", "replace")
    plen = read_exact(sock, 1)[0]
    password = read_exact(sock, plen).decode("utf-8", "replace")
    return user, password


def parse_request(sock):
    """Returns (cmd, host, port). Raises on malformed input."""
    ver, cmd, _rsv, atyp = read_exact(sock, 4)
    if ver != SOCKS_VER:
        raise OSError("bad socks version 0x%02x" % ver)

    if atyp == ATYP_IPV4:
        host = socket.inet_ntop(socket.AF_INET, read_exact(sock, 4))
    elif atyp == ATYP_IPV6:
        host = socket.inet_ntop(socket.AF_INET6, read_exact(sock, 16))
    elif atyp == ATYP_DOMAIN:
        length = read_exact(sock, 1)[0]
        host = read_exact(sock, length).decode("idna")
    else:
        raise OSError("unknown address type 0x%02x" % atyp)

    port = int.from_bytes(read_exact(sock, 2), "big")
    return cmd, host, port


def open_tunnel(host, port, cfg):
    """
    Reach host:port through the front proxy when one is configured.
    Returns a connected socket, or raises OSError.
    """
    if not cfg.front_host:
        log("direct ->", "%s:%d" % (host, port))
        return socket.create_connection((host, port), timeout=cfg.timeout)

    upstream = socket.create_connection(
        (cfg.front_host, cfg.front_port), timeout=cfg.timeout
    )
    upstream.settimeout(cfg.timeout)
    target = f"{host}:{port}"
    request = [f"CONNECT {target} HTTP/1.1", f"Host: {target}", "Proxy-Connection: Keep-Alive"]
    if cfg.front_user:
        request.append(basic_auth(cfg.front_user, cfg.front_pass))
    request.append("")
    request.append("")

    upstream.sendall("\r\n".join(request).encode())
    response = recv_headers(upstream)
    if response is None:
        upstream.close()
        raise OSError("front proxy closed the CONNECT handshake")

    status_line = response.split(b"\r\n", 1)[0].decode("latin-1", "replace")
    if " 200 " not in status_line:
        upstream.close()
        raise OSError("front proxy refused CONNECT: %s" % status_line)

    log("via front", cfg.front_host, "->", target, "|", status_line)
    upstream.settimeout(None)
    return upstream


def open_to_target(cfg):
    """The gateway leg: HTTP CONNECT + Basic auth, straight to Bright Data."""
    sock = open_tunnel(cfg.target_host, cfg.target_port, cfg)
    target = f"{cfg.target_host}:{cfg.target_port}"
    request = [
        f"CONNECT {target} HTTP/1.1",
        f"Host: {target}",
        basic_auth(cfg.target_user, cfg.target_pass),
        "",
        "",
    ]
    sock.sendall("\r\n".join(request).encode())

    response = recv_headers(sock)
    if response is None:
        sock.close()
        raise OSError("gateway closed the CONNECT handshake")

    status_line = response.split(b"\r\n", 1)[0].decode("latin-1", "replace")
    body = response.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in response else b""

    if " 200 " not in status_line:
        sock.close()
        hint = ""
        if b"ip_blacklisted" in response:
            hint = "  <- source IP is denied by the zone; change --front-*"
        elif b"x-brd-err-code" in response:
            for line in response.decode("latin-1", "replace").split("\r\n"):
                if line.lower().startswith("x-brd-err"):
                    hint = "  <- " + line
                    break
        raise OSError("gateway refused: %s%s" % (status_line, hint))

    log("gateway ok |", status_line, "|", body.decode("latin-1", "replace").strip())
    sock.settimeout(None)
    return sock


def pipe(a, b):
    """Bidirectional copy until either side closes."""
    sel = selectors.DefaultSelector()
    sel.register(a, selectors.EVENT_READ, b)
    sel.register(b, selectors.EVENT_READ, a)
    try:
        while True:
            for key, _mask in sel.select(timeout=60):
                src, dst = key.fileobj, key.data
                try:
                    chunk = src.recv(65536)
                except OSError:
                    return
                if not chunk:
                    return
                try:
                    dst.sendall(chunk)
                except OSError:
                    return
    finally:
        sel.close()


def handle_client(client, cfg):
    peer = client.getpeername()
    upstream = None
    try:
        client.settimeout(cfg.timeout)

        method = parse_greeting(client, METHOD_USERPASS if cfg.auth_user else METHOD_NO_AUTH)
        if method is None:
            client.sendall(bytes([SOCKS_VER, METHOD_NONE_ACCEPTABLE]))
            log("client offered no acceptable auth method, from", peer[0])
            return
        client.sendall(bytes([SOCKS_VER, method]))

        if method == METHOD_USERPASS:
            user, password = parse_userpass(sock=client)
            user_ok = hmac.compare_digest(user, cfg.auth_user)
            pass_ok = hmac.compare_digest(password, cfg.auth_pass)
            client.sendall(bytes([0x01, 0x00 if (user_ok and pass_ok) else 0x01]))
            if not (user_ok and pass_ok):
                log("bad credentials from", peer[0], "user=%r" % user)
                return

        cmd, host, port = parse_request(client)
        if cmd != CMD_CONNECT:
            send_socks_reply(client, REPLY_CMD_NOT_SUPPORTED)
            log("refused non-CONNECT command 0x%02x from %s" % (cmd, peer[0]))
            return

        upstream = open_to_target(cfg)
        send_socks_reply(client, REPLY_OK)
        log("open", f"{peer[0]}:{peer[1]}", "->", f"{host}:{port}")
        pipe(client, upstream)
    except OSError as exc:
        log("error from %s: %s" % (peer[0], exc))
        try:
            send_socks_reply(client, REPLY_GENERAL_FAILURE)
        except OSError:
            pass
    finally:
        for sock in (client, upstream):
            if sock is None:
                continue
            try:
                sock.close()
            except OSError:
                pass


def serve(cfg):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((cfg.listen_host, cfg.listen_port))
    listener.listen(128)
    log(f"listening on {cfg.listen_host}:{cfg.listen_port}")
    log(f"chain: [front {cfg.front_host or 'none'}:{cfg.front_port or '-'}]"
        f" -> {cfg.target_host}:{cfg.target_port}")
    if not cfg.front_host:
        log("NOTE: no front proxy configured, this is the same path as a direct client")
    if cfg.listen_host not in ("127.0.0.1", "localhost", "::1") and not cfg.auth_user:
        log("WARNING: public bind with NO auth. Set RELAY_USER/RELAY_PASS or firewall this port.")

    print(f"socks5://{cfg.listen_host}:{cfg.listen_port} ready", flush=True)

    while True:
        client, _addr = listener.accept()
        threading.Thread(target=handle_client, args=(client, cfg), daemon=True).start()


# ---------------------------------------------------------------- self-test

def socks5_open(cfg, host, port):
    sock = socket.create_connection((cfg.listen_host, cfg.listen_port), timeout=30)

    if cfg.auth_user:
        sock.sendall(bytes([SOCKS_VER, 2, METHOD_NO_AUTH, METHOD_USERPASS]))
    else:
        sock.sendall(bytes([SOCKS_VER, 1, METHOD_NO_AUTH]))
    chosen = sock.recv(2)
    if len(chosen) < 2 or chosen[1] == METHOD_NONE_ACCEPTABLE:
        raise OSError("relay refused our auth method")

    if chosen[1] == METHOD_USERPASS:
        user = cfg.auth_user.encode()
        password = cfg.auth_pass.encode()
        sock.sendall(bytes([0x01, len(user)]) + user + bytes([len(password)]) + password)
        status = sock.recv(2)
        if status[1] != 0x00:
            raise OSError("relay rejected our credentials")

    req = bytes([SOCKS_VER, CMD_CONNECT, 0x00, ATYP_DOMAIN, len(host)]) + host.encode()
    sock.sendall(req + port.to_bytes(2, "big"))
    head = sock.recv(4)
    if head[1] != REPLY_OK:
        raise OSError("SOCKS5 reply code 0x%02x" % head[1])
    sock.recv(4 + 2)
    return sock


def run_check(cfg):
    url = "geo.brdtest.com"
    path = "/welcome.txt?product=isp&method=native"
    log("checking via", url + path)
    sock = socks5_open(cfg, url, 443)
    ctx = ssl.create_default_context()
    tls = ctx.wrap_socket(sock, server_hostname=url)
    tls.sendall(f"GET {path} HTTP/1.1\r\nHost: {url}\r\nConnection: close\r\n\r\n".encode())
    raw = b""
    while True:
        chunk = tls.recv(65536)
        if not chunk:
            break
        raw += chunk
    tls.close()
    print(raw.decode("utf-8", "replace"))


def build_parser():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--listen-host", default=os.environ.get("LISTEN_HOST", "127.0.0.1"))
    p.add_argument("--listen-port", type=int, default=int(os.environ.get("LISTEN_PORT", "1080")))
    p.add_argument("--target-host", default=os.environ.get("TARGET_HOST", "brd.superproxy.io"))
    p.add_argument("--target-port", type=int, default=int(os.environ.get("TARGET_PORT", "44445")))
    p.add_argument("--target-user", default=os.environ.get("BRD_USER", ""))
    p.add_argument("--target-pass", default=os.environ.get("BRD_PASS", ""))
    p.add_argument("--front-host", default=os.environ.get("FRONT_HOST", ""))
    p.add_argument("--front-port", type=int, default=int(os.environ.get("FRONT_PORT", "0")))
    p.add_argument("--front-user", default=os.environ.get("FRONT_USER", ""))
    p.add_argument("--front-pass", default=os.environ.get("FRONT_PASS", ""))
    p.add_argument("--auth-user", default=os.environ.get("RELAY_USER", ""),
                   help="SOCKS5 username clients must present; mandatory in practice "
                        "on a public bind")
    p.add_argument("--auth-pass", default=os.environ.get("RELAY_PASS", ""))
    p.add_argument("--timeout", type=int, default=30)
    p.add_argument("--check", action="store_true",
                   help="run one geo test request through the chain and exit")
    p.add_argument("-v", "--verbose", action="store_true")
    return p


def main():
    global VERBOSE
    cfg = build_parser().parse_args()
    VERBOSE = cfg.verbose or cfg.check

    if not cfg.target_user:
        sys.exit("error: BRD_USER (or --target-user) is required")

    if cfg.check:
        try:
            run_check(cfg)
        except OSError as exc:
            sys.exit("check failed: %s" % exc)
        return

    try:
        serve(cfg)
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()