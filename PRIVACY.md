# Privacy Policy — ecsctl bar

Effective: 2026-07-25

ecsctl bar is a macOS menu bar utility for operating your own Amazon ECS
fleet. It is designed to collect nothing.

## What the app accesses

- **AWS credentials**: obtained on your Mac either via AWS IAM Identity
  Center (SSO) sign-in that you initiate, or from your local AWS
  configuration. Credentials are stored only in your macOS Keychain and are
  used exclusively to call AWS APIs on your behalf.
- **ecsctl configuration** (`config.toml`): read only if you explicitly
  select it via the import dialog. A copy is kept inside the app's sandbox
  container.

## What the app collects

Nothing. The app has no analytics, no tracking, no telemetry, no ads, and
no server of its own. Your data never leaves your Mac except for the AWS
API calls the app makes directly to your AWS account and Apple's App Store
services for subscription management.

## Third parties

- **AWS**: the app talks directly to AWS endpoints (SSO OIDC, SSO portal,
  Amazon ECS) using your credentials. Governed by your agreement with AWS.
- **Apple**: subscription purchase and management are handled by the App
  Store. Governed by Apple's privacy policy.

## Contact

Open an issue at https://github.com/oablab/ecsctl-bar/issues
