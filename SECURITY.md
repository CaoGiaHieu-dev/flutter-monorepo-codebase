# Security Policy

## Supported versions

This repository is a template, not a released library. Only the latest `main` receives security
fixes; tagged releases (`vX.Y.Z`, see [CHANGELOG.md](CHANGELOG.md)) are snapshots and are not
patched after the fact. A project generated from the template owns its own copy — pull fixes from
`main` into it yourself.

| Version | Supported |
|:--|:--|
| `main` (latest) | Yes |
| Anything older | No |

## Reporting a vulnerability

**Do not open a public issue, discussion or pull request for a security problem.**

1. Preferred: use GitHub's private vulnerability reporting — **Security → Report a vulnerability**
   on this repository (a draft security advisory visible only to the maintainers).
2. If that is unavailable, email **security@your-domain.example** *(placeholder — the maintainer
   replaces this with a monitored address)*.

Include the affected path(s), the flavor and build mode (`dev` / `staging` / `prod`, debug or
release), steps to reproduce, and the impact you see. We aim to acknowledge within 5 working days
and to agree a disclosure date with you once a fix is ready; we credit reporters in the advisory
unless you ask us not to.

## Scope notes — read before reporting

These are deliberate and documented, so they are **not** vulnerabilities in themselves:

- **The committed dev keystore is public.** `apps/mobile/android/keystore-dev.jks` and
  `apps/mobile/android/key-dev.properties` are tracked so a fresh clone can build the `dev` flavor.
  Anyone can sign with that key. Gradle falls back to it for staging/prod when the real
  `key.properties` / `key-stg.properties` is absent — never ship a store build signed with it. See
  [`docs/en/operations/02_fastlane_release.md` § 4](docs/en/operations/02_fastlane_release.md).
- **SSL pinning is off until you configure it.** The template apps declare
  `ssl_pinning: { disabled: … }` for staging and prod in `apps/mobile/app_manifest.yaml` and
  `apps/admin/app_manifest.yaml`, so they use normal certificate validation only (and each app's
  report lists it under *decisions to revisit*).
  Declare at least two SPKI hashes (leaf + backup) per flavor before relying on pinning — see [`docs/en/guides/08_networking.md` § 10](docs/en/guides/08_networking.md#10-turn-on-ssl-pinning). Pins apply to every host the process connects to, not only your API: an image CDN, a font host or a third-party SDK endpoint with no matching pin fails its handshake too.
- **The pinning plugin's probe accepts any certificate, on purpose.** To read the chain a host
  presents, `http_security_pinning` opens an unauthenticated observation connection (Android: an
  accept-all trust manager; iOS: a challenge it cancels; desktop: `onBadCertificate` returns true)
  and trusts nothing from it. Enforcement is the second, real connection, whose `SecurityContext`
  holds only the certificates that matched your pins. A scanner finding on the probe is expected; a
  pin that does not stop a mismatching host is a vulnerability: report it.
- **Certificate validation is bypassed only in a debug build that explicitly declared
  `--flavor dev`.** A missing or unknown flavor is treated as prod. A bypass reachable any other
  way *is* a vulnerability — please report it.
- **`env.dev` / `env.stg` are committed on purpose** and hold no secrets.

Secrets are never committed. If you find any of the following in the history, report it privately:
`env.prod`, `key.properties` / `key-*.properties` other than `key-dev.properties`, any release
`*.jks` / `*.keystore`, `google-services.json`, `GoogleService-Info.plist`,
`firebase_options_*.dart`, fastlane `Config.yaml`, App Store Connect `.p8` keys, or the
`tools/code_review/.gemini_api_key` file. CI receives these through repository secrets only
(see [`.github/SETUP_GUIDE.md`](.github/SETUP_GUIDE.md)).

## For projects built on this template

- Decide `flavors.<f>.ssl_pinning` in your app manifest (at least two pins, or `disabled` with a
  reason). The decision is the app's `SslPinningPolicy`, which `AppInitializer` installs before DI
  starts; there is no pin to register or bind and no constant in `platform/` to edit. The pins cover
  every host the app connects to (check CDNs and SDK endpoints first), and the bearer token goes only
  to the API host and `NetworkProfile.authorizedHosts` — declare both together when the API spans
  several domains.
- Generate your own release keystores and keep them out of git.
- Replace the placeholder contact above and enable private vulnerability reporting in your fork.
