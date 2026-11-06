# client-version

One protocol for "which build of the app is this?" and "you should / must upgrade", shared by every
app and server we build. Read [SPEC.md](SPEC.md); `cases.json` is the conformance fixture every
implementation runs.

| Implementation | Where | Use from |
|----------------|-------|----------|
| TypeScript (servers, Workers, web) | `src/index.ts` (root `package.json`) | `"@omumu/client-version": "github:omumuas/client-version"` |
| Swift (Mac/iOS apps) | `Sources/ClientVersion` (root `Package.swift`) | `.package(url: "git@github.com:omumuas/client-version.git", from: "1.0.0")` |
| Dart (Flutter apps) | `dart/` (`package:client_version`, incl. a Dio interceptor) | `client_version: {git: {url: https://github.com/omumuas/client-version.git, path: dart, ref: v1.1.0}}` |
| Java (servlets) | `com.omumu.gabbro.clientversion` in `omumuas/modules` (`ClientVersionFilter`, `DynaPropsClientVersionPolicy`); runs a copy of this `cases.json` | `com.omumu:gabbro` |

In short:
- Apps send `X-Client-Version: fleshtimer/1.2.0+42 (macos)` on every request.
- Per app and platform the server keeps `minimum` (hard) and `recommended` (soft) versions.
- Below `recommended`: `X-Client-Upgrade: recommended` (a dismissible nudge). Below `minimum`:
  `X-Client-Upgrade: required`; reads are still served, writes get `426 upgrade_required`.
- Unknown or missing versions count as current. Handlers gate behaviour with `atLeast(client, "1.3")`.

## Tests

```bash
npm test          # TypeScript against cases.json
npm run typecheck
swift test        # Swift against cases.json
(cd dart && dart test)   # Dart against cases.json
```

When `cases.json` changes, copy it to `modules/gabbro/src/test/resources/com/omumu/gabbro/clientversion/`.
Servers apply the check to their application API, never to authentication endpoints (SPEC.md, Scope).
