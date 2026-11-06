# Client version protocol, v1

How an app tells a server which build it is, and how the server answers "you should upgrade" (soft)
or "you must upgrade" (hard) while it keeps serving older apps for as long as it can.

`cases.json` is the conformance fixture: every implementation (TypeScript, Swift, Dart, Java) must
pass all of it. Change the fixture first when the behaviour changes.

## Request: `X-Client-Version`

Every request from an app carries:

```
X-Client-Version: <app>/<version>[+<build>] (<platform>)
```

| Part       | Rule                                                                 | Example        |
|------------|----------------------------------------------------------------------|----------------|
| `app`      | lower case `[a-z][a-z0-9-]*`, one name per product across platforms  | `fleshtimer`   |
| `version`  | 1 to 4 dot-separated non-negative integers (marketing version)       | `1.2.0`        |
| `build`    | optional, `[0-9A-Za-z.-]+`; informational, never compared            | `42`           |
| `platform` | lower case `[a-z][a-z0-9-]*`: `macos`, `ios`, `android`, `web`, ...  | `macos`        |

Example: `X-Client-Version: fleshtimer/1.2.0+42 (macos)`.

A dedicated header, not `User-Agent`: browsers and WebSocket clients cannot set `User-Agent`
reliably. Where no header can be sent (a browser WebSocket), the same value goes in the query
parameter `client_version`; the header wins when both are present.

Parsing trims surrounding whitespace. Anything that does not match is **unknown** (see below), never
an error: a server must not refuse a request because of a malformed version.

## Comparing versions

Numeric, component by component; a missing component is 0 (`1.2` = `1.2.0` = `1.2.0.0`). The
build is ignored. Leading zeros are allowed and do not matter (`1.02` = `1.2`).

## Policy

The server keeps, per app and platform:

| Field         | Meaning                                                                      |
|---------------|------------------------------------------------------------------------------|
| `minimum`     | Oldest version still allowed to write. Below it: **required**.               |
| `recommended` | Oldest version that is not nudged. Below it (and at or above `minimum`): **recommended**. |
| `upgradeUrl`  | Where the app sends the user (store page). Optional.                         |

Both versions are optional. The policy lives where it can change without a deploy (a table, dynamic
properties), because the soft threshold moves when a store release is approved, not when the server
ships.

## Evaluation

`evaluate(policy, clientVersion)` gives one of:

| Level         | When                                                                 |
|---------------|----------------------------------------------------------------------|
| `none`        | unknown client (missing or unparseable header), no policy for its app/platform, or version ≥ `recommended` (or no `recommended`) and ≥ `minimum` |
| `recommended` | version < `recommended`, and ≥ `minimum` (or no `minimum`)           |
| `required`    | version < `minimum`                                                  |

An unknown client is treated as current. This keeps first-party web clients (served with the
server, always current) and tools like `curl` working, and it means sending the header is what opts
an app into the protocol.

## Response

| Level         | Safe methods (`GET`, `HEAD`, `OPTIONS`, WebSocket upgrade) | Other methods (writes) |
|---------------|------------------------------------------------------------|------------------------|
| `none`        | served, no extra headers                                   | served                 |
| `recommended` | served, with the headers below                             | served, with the headers |
| `required`    | served, with the headers below                             | **refused**: `426`     |

Headers on `recommended` and `required` responses (including the 426):

```
X-Client-Upgrade: recommended | required
X-Upgrade-URL: <upgradeUrl>            (only when the policy has one)
```

The refusal:

```
HTTP/1.1 426 Upgrade Required
Content-Type: application/json
X-Client-Upgrade: required
X-Upgrade-URL: https://apps.apple.com/app/id6830173151

{ "error": "upgrade_required", "message": "This version of the app is no longer supported. Please update.", "upgradeUrl": "https://apps.apple.com/app/id6830173151" }
```

`upgradeUrl` is omitted from the body when the policy has none. Servers that expose headers to
browsers list `X-Client-Upgrade, X-Upgrade-URL` in `Access-Control-Expose-Headers` and accept
`X-Client-Version` in `Access-Control-Allow-Headers`.

Reads keep working below `minimum` on purpose: an outdated app can still show the user their data,
and cannot corrupt it.

## Client behaviour

- Send `X-Client-Version` on every request (and `client_version` on WebSocket URLs).
- `X-Client-Upgrade: recommended` → a dismissible nudge. Remember the dismissal per app version, so
  it comes back after the next release but not on every launch.
- `X-Client-Upgrade: required` or a `426` → a persistent banner or screen with an Update button;
  writes stay disabled until the app is updated. Reads continue. A 426 is not retried.
- Prefer `X-Upgrade-URL` over a hardcoded store link; fall back to the hardcoded one.
- The latest header seen wins: a response with no `X-Client-Upgrade` clears the state (the policy
  may have been relaxed).

## Serving older clients (version gating)

The server parses the client version once per request and lets handlers ask
`atLeast(client, "1.3")`. An unknown client counts as at least every version (current). Use it to:

- keep an old response shape for old clients when a field changes meaning;
- leave out data an old client cannot render;
- refuse one feature with `426` while the rest of the app keeps working.

Prefer additive changes (new optional fields) that need no gate at all. A new path version
(`/api/v2`) is for a break too large to serve both shapes from one handler.
