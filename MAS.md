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

## Remaining work for submission

- [ ] Sandboxed build target: entitlements (`app-sandbox`, `network.client`,
      user-selected file read), bundled ecsctl (darwin-arm64 from ecsctl release,
      inherit-signed), MAS provisioning + signing
- [ ] Make MAS build NEVER probe external ecsctl paths (bundled only)
- [ ] Config import flow (security-scoped bookmark + fallback sync, above)
- [ ] Verify subprocess sandbox-extension inheritance (item 3 above)
- [ ] Demo mode with canned fleet data — App Review can't log into AWS
- [ ] ASC upload: reuse foldic pipeline (`~/repo/foldic/scripts/asc_jwt.py` +
      `asc_upload.py`), new app record in App Store Connect
- [ ] Review notes: explain SSO device flow + demo mode credentials

## Review risks (acknowledged)

- Niche dev tool + reviewer can't reach a real AWS account → demo mode is load-bearing
- Guideline 2.4.5 (no downloaded code): satisfied — helper is bundled + signed;
  ensure zero fallback to external binaries in the MAS build
