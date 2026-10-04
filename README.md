# brdchain

A tiny SOCKS5 relay that reaches a **Bright Data ISP zone** from an address that
zone is willing to accept.

```
your client  ->  socks5://relay:1080        <- brdchain.py, user/pass auth
             ->  FRONT proxy                 <- HTTP CONNECT, optional
             ->  brd.superproxy.io:44445     <- HTTP gateway + Basic auth
             ->  destination
```

## The problem it solves

Bright Data ISP zones enforce an ACL on the **source** IP. Connect from an
address the zone does not like and you get:

```
HTTP/1.1 401 Auth Failed (code: ip_blacklisted)
x-brd-err-code: client_10050
details="destination_ip_prohibited"; The IP address from which you are sending
this request: 203.0.113.10 is denylisted in this zone's settings.
```

Nothing on the client side fixes that — not curl flags, not the browser, not the
launcher. The only move is to arrive at the gateway from a different address.
`brdchain` is that address, and because it is a separate process it can live on
a €4/mo VPS instead of dying every time you close the laptop lid.

## Requirements

Python 3.9+. No dependencies, no pip, one file.

## Configure

Everything is a flag or an environment variable. See `.env.example`.

| What | Flag | Env | Meaning |
|------|------|-----|---------|
| Bright Data login | `--target-user` | `BRD_USER` | `brd-customer-hl_XXXX-zone-isp_proxy1` |
| Bright Data password | `--target-pass` | `BRD_PASS` | |
| Gateway | `--target-host/--target-port` | `TARGET_HOST/PORT` | `brd.superproxy.io:44445` |
| Front hop | `--front-host/--front-port` | `FRONT_HOST/PORT` | leave empty if the host itself already exits in an allowed country |
| Front credentials | `--front-user/--front-pass` | `FRONT_USER/PASS` | |
| Relay listen | `--listen-host/--listen-port` | `LISTEN_HOST/PORT` | default `127.0.0.1:1080` |
| Relay credentials | `--auth-user/--auth-pass` | `RELAY_USER/RELAY_PASS` | SOCKS5 user/pass required from clients |

`--front-*` empty is a valid configuration: then the relay connects straight to
the gateway and relies on the host's own VPN/WireGuard exit. Good for a VPS in
a permitted country.

## Verify before deploying anything

```bash
python3 brdchain.py --check \
  --target-user "$BRD_USER" --target-pass "$BRD_PASS" \
  --front-host H --front-port P --front-user U --front-pass W
```

One live request to `geo.brdtest.com/welcome.txt?product=isp&method=native`
through the whole chain, printed raw. If it comes back as a native ISP address
rather than a datacenter one, the chain is good.

`ip_blacklisted` in the output means the front hop is also denied — change it.

## Deploy

### Fly.io (the cheap always-on option)

```bash
fly auth login
fly launch --no-deploy        # fly.toml is already in the repo
fly secrets set BRD_USER=... BRD_PASS=... RELAY_USER=... RELAY_PASS=...
fly secrets set FRONT_HOST=... FRONT_PORT=... FRONT_USER=... FRONT_PASS=...
fly deploy
fly ips allocate
```

`min_machines_running = 1` plus `auto_stop_machines = "suspend"` means it stays
reachable when you want it and does not burn money while you sleep. Port 1080 is
a raw `tcp` handler — SOCKS5 is not HTTP, there is nothing to terminate.

### Docker anywhere

```bash
cp .env.example .env      # fill it in
docker compose up -d
```

### Plain VPS, systemd, always on

```bash
sudo install -m 755 brdchain.py /opt/brdchain/brdchain.py
sudo install -m 600 .env  /etc/brdchain.env
sudo install -m 644 brdchain.service /etc/systemd/system/brdchain.service
sudo systemctl enable --now brdchain
journalctl -u brdchain -f
```

## Client

```bash
curl --socks5-hostname RELAY:1080 --proxy-user "$RELAY_USER:$RELAY_PASS" \
     https://geo.brdtest.com/welcome.txt?product=isp&method=native
```

In an anti-detect launcher that supports `scheme://user:pass@host:port`:

```
socks5://RELAY_USER:RELAY_PASS@relay.example.com:1080
```

## Security

The relay is a paid proxy with your credentials baked into one leg of it. Treat
the listening port accordingly:

- **always set `RELAY_USER` / `RELAY_PASS`** when the bind address is not
  loopback. Open SOCKS5 on a public IP gets found by scanners within hours.
- better still, firewall 1080 to your own IP, or put the relay on a private
  network (Tailscale / WireGuard) and bind to the interface address.
- `brdchain.service` runs as `nobody` with `ProtectSystem=strict` and the rest
  of the systemd sandbox; the process writes nothing and needs no capabilities.
- rotate the Bright Data password after it has been in any chat, log or shell
  history. `BRD_PASS` lives in the environment, so it will not end up in `ps`.

## Limitations

- CONNECT only. No `UDP_ASSOCIATE`, so QUIC and WebRTC over UDP will fall back
  to TCP. Browsers handle this automatically; a client that *requires* UDP will
  not work through this.
- No connection pooling: each client CONNECT opens its own gateway tunnel.
  Fine for a handful of profiles, not built for thousands.
- Not an anonymity layer on its own — the front hop sees the destination, and
  Bright Data sees the front hop. Pair it with a matching timezone/locale if the
  destination cares.

## Tests

```bash
python3 test_brdchain.py brdchain.py
```

Spins up a mock front proxy, a mock gateway and an echo server on loopback, then
drives a real SOCKS5 client through the relay and asserts: no-auth is refused,
a wrong password is refused, the correct password yields a working tunnel, and
both upstream legs carry `Proxy-Authorization`. No network, no credentials.

## Licence

MIT.