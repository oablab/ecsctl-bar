# MAS Plan — ecsctl-bar Mac App Store build

Status: **design + groundwork done, sandboxed target not built yet** (2026-07-25)

## Why a separate build

MAS mandates App Sandbox. The current (ad-hoc / Developer ID) build shells out to an
external `ecsctl` and reads `~/.aws` + `~/.ecsctl` — all blocked under sandbox.
The Developer ID build stays as-is for CLI users; MAS gets a self-contained variant.

## Architecture (decided)

| Concern | Non-MAS build (today) | MAS build |
|---|---|---|
| ecsctl binary | probes `~/.local/bin` etc. | bundled at `Contents/Helpers/ecsctl`, signed with `com.apple.security.inherit` (probe already prefers this path) |
| AWS credentials | `~/.aws` default chain | in-app SSO device flow → env vars injected into subprocess (`Sources/SSO.swift`, done + verified) |
| Config (`[groups]`) | `~/.ecsctl/config.toml` | `ECSCTL_CONFIG` → app container; seeded by import (below) |
| Region | from `~/.aws` profile | `AWS_REGION` from SSO popover ("fleet" field) |

## Groundwork already shipped

- **ecsctl PR #54** — `ECSCTL_CONFIG` env var overrides config path (merged, oablab/ecsctl master)
- **`Sources/SSO.swift`** — full SSO device-authorization flow in-process:
  RegisterClient → StartDeviceAuthorization → browser approval → CreateToken poll →
  ListAccounts/ListAccountRoles picker → GetRoleCredentials. Session persisted in
  Keychain, credentials auto-renewed (60 s timer) while token valid.
  Verified end-to-end 2026-07-25: child ecsctl processes carry `AWS_ACCESS_KEY_ID=ASIA…`,
  `AWS_SESSION_TOKEN`, `AWS_REGION` (checked via `ps eww`).
- **`main.swift`** — bundled-binary probe first; `runProcess` merges `CredentialBridge`
  env + forwards `ECSCTL_CONFIG`; `GroupConfig` honors `ECSCTL_CONFIG`.
- Signed-out behavior unchanged: empty bridge → ecsctl falls back to `~/.aws`
  (only meaningful in the non-MAS build).

## Config import/sharing design (decided, not implemented)

Target user: existing ecsctl CLI user with a working `~/.ecsctl/config.toml`.

1. First run: "Share your ecsctl CLI config" → `NSOpenPanel` with
   `directoryURL = ~/.ecsctl` (hidden dir is fine — powerbox renders it)
2. One selection of `config.toml` → save a **security-scoped bookmark** →
   live-read the real file on every refresh. Shared with the CLI, not a snapshot.
3. **Must verify in the sandboxed build:** whether the inherit-sandboxed child
   (bundled ecsctl) can read through the parent's security-scoped extension.
   - Fallback if not (no UX cost): app copies the file into its container on
     mtime change and points `ECSCTL_CONFIG` at the copy. Safe because the whole
     pipeline is read-only — the app only runs `get/scale/restart/update/export`,
     none of which write config. One-way CLI→app sync, no conflict case.
4. No CLI config? Skip import — Services view needs zero config; Groups tab shows
   an empty state ("import CLI config or create groups here").

## Sandboxed prototype — VALIDATED 2026-07-25 (`build-mas.sh`)

`ecsctl-bar-mas.app`: ad-hoc signed with real sandbox entitlements (sandbox fully
enforced — container created). Full fleet table rendered under sandbox with:
in-app SSO sign-in (Keychain-restored across builds) + bundled inherit-signed
helper + imported config via `ECSCTL_CONFIG` → container copy.

Findings:

- **`ecsctl get --all` is alias-driven** — without config it returns an empty
  list, so config import is load-bearing for the Services view too, not just
  Groups. First-run empty state now shows the import button inline.
- **Bundled ecsctl MUST be post-PR#54** (`ECSCTL_CONFIG` support). A pre-#54
  binary silently ignores the env var → empty list with no error. Cut an ecsctl
  release (v0.12.x) and bundle from the tagged artifact, not a dev build.
- **Security-scoped bookmark creation fails under ad-hoc signing** even with
  `com.apple.security.files.bookmarks.app-scope` (app-scoped bookmarks need a
  stable code identity). The immediate-copy fallback in `ConfigShare` carries
  the flow: import works, but the config is a static snapshot until re-import.
  → RETEST bookmarks with Developer ID / MAS signing; if still failing, add a
  "Re-import" button for config changes.
- No sandbox denials for the child reading the container copy (inherit works
  for container files as designed).
- Keychain note: the sandboxed app triggers one approval prompt to reuse the
  SSO session item created by the non-sandboxed build (different code identity).
  Fresh installs won't see this.

## Remaining work for submission

- [ ] Release ecsctl v0.12.x; bundle darwin-arm64 from the tagged release
- [ ] Real signing (Developer ID for local test, then MAS cert): retest
      security-scoped bookmark persistence
- [ ] Make MAS build NEVER probe external ecsctl paths (bundled only)
- [ ] Demo mode with canned fleet data — App Review can't log into AWS
- [ ] ASC upload: reuse foldic pipeline (`~/repo/foldic/scripts/asc_jwt.py` +
      `asc_upload.py`), new app record in App Store Connect
- [ ] Review notes: explain SSO device flow + demo mode credentials

## Review risks (acknowledged)

- Niche dev tool + reviewer can't reach a real AWS account → demo mode is load-bearing
- Guideline 2.4.5 (no downloaded code): satisfied — helper is bundled + signed;
  ensure zero fallback to external binaries in the MAS build
