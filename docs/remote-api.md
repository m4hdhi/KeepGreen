# KeepGreen Remote API, version 1

The desktop apps (Windows and macOS) can be watched and controlled from the KeepGreen phone apps (iOS and Android) over the local network. This document is the contract every app implements. Change it here first.

The remote is **off by default**. People turn it on in the desktop app under *Settings → Phone remote*.

## Transport

- Plain HTTP/1.1 over TCP on **port 47321**, listening on all IPv4 interfaces of the desktop.
- Request and response bodies are UTF-8 JSON (`Content-Type: application/json`). Property names are camelCase.
- The server answers one request per connection and then closes it (`Connection: close`). Clients must not rely on keep-alive.
- Bodies larger than 4 KB are rejected. A connection that doesn't finish its request within 10 seconds is dropped.
- Errors return a status code and `{"error": "human readable message"}`:
  `400` malformed request or JSON, `401` bad pairing code, signature or clock, `404` unknown path, `405` wrong method, `429` too many pairing attempts.

## Discovery and pairing

The desktop shows, while the remote is on:

- its address(es) on the local network, e.g. `192.168.1.20:47321`;
- a **6-digit pairing code**, valid for 10 minutes and replaced after it expires, after a successful pairing, or after 5 wrong attempts;
- where it can draw one (macOS), a QR code of the **pairing link**:
  `keepgreen://pair?host=192.168.1.20&port=47321&code=123456&name=Mahdhi%E2%80%99s%20PC`

The phone pairs once:

```
POST /v1/pair
{"code": "123456", "device": "Mahdhi's iPhone"}
```

`200` returns the shared key and the desktop's identity:

```json
{"key": "3f1c9a0b5e7d42c8a1b6e0f9d3c5a7b1", "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}
```

- `key` is 16 random bytes as 32 lowercase hex characters. Every paired phone of that desktop gets the same key. *Unpair all phones* on the desktop makes a new key, which signs all phones out.
- Wrong or expired code: `401`. After 5 wrong attempts the code is replaced and the endpoint answers `429` for 60 seconds.
- The key travels once, in clear, on the local network. All later requests are signed and never contain the key.

Phones keep a list of paired desktops (`host`, `port`, `key`, `name`, `platform`).

An unsigned health check is available before pairing:

```
GET /v1/ping  ->  {"app": "KeepGreen", "api": 1, "name": "DESKTOP-ABC", "platform": "windows", "version": "2.0.0"}
```

## Signed requests

Every endpoint except `/v1/ping` and `/v1/pair` needs two headers:

| Header | Value |
| --- | --- |
| `X-KeepGreen-Time` | Unix time in whole seconds, e.g. `1793876400` |
| `X-KeepGreen-Signature` | lowercase hex `HMAC-SHA256(key, message)` |

- The HMAC key is the **UTF-8 bytes of the 32-character hex key string** (not the decoded 16 bytes).
- `message` is `METHOD + "\n" + PATH + "\n" + TIME + "\n" + BODY`:
  `METHOD` upper case (`GET`, `POST`), `PATH` without query string (`/v1/status`), `TIME` the exact header value, `BODY` the exact request body (`""` for GET).
- The server rejects the request with `401` if the signature doesn't match, or if its clock and `TIME` differ by more than 120 seconds.

Test vector (every app has a unit test for it):

```
key       = "00112233445566778899aabbccddeeff"
message   = "GET\n/v1/status\n1700000000\n"        (method GET, path /v1/status, time 1700000000, empty body)
signature = "e61ba19958971173e1d8eb4038ff25f241eb73396f25529d28cfd3d602fd5e80"
```

## Endpoints

| Method | Path | Body | What it does |
| --- | --- | --- | --- |
| GET | `/v1/status` | | Current status |
| POST | `/v1/enabled` | `{"enabled": true}` | Flip the master switch |
| POST | `/v1/boost` | `{"minutes": 60}` (1 to 720) or `{"untilEndOfWorkday": true}` | Start a boost |
| POST | `/v1/boost/cancel` | `{}` | End the boost |

All four return the **status object**:

```json
{
  "name": "DESKTOP-ABC",
  "platform": "windows",
  "version": "2.0.0",
  "state": "Active",
  "isActive": true,
  "isEnabled": true,
  "isBoosted": false,
  "boostUntil": null,
  "headline": "You're staying green",
  "detail": "Work hours end today at 17:00.",
  "idleSeconds": 12,
  "nudgesToday": 87,
  "greenSecondsToday": 22320
}
```

- `platform` is `windows` or `macos`.
- `state` is one of `Active`, `Disabled`, `OffSchedule`, `DayOff`, `Break`, `Locked`, `OnBattery`, `LowBattery`, `WaitingForApp`. Clients show unknown values as a neutral state.
- `boostUntil` is `null` or ISO 8601 with offset, e.g. `"2026-11-05T14:30:00+04:00"`.
- `headline` and `detail` are the same friendly sentences the desktop dashboard shows; phones display them as-is.
- Status colours: `Active` green, `Disabled` grey, everything else amber.
