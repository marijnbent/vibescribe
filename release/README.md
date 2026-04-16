# Local Release

Canonical local release commands:

```bash
./scripts/build-release.sh
./scripts/release-local.sh
```

`./scripts/build-release.sh` builds a signed app bundle at `build/Release/Talkie.app`.

`./scripts/release-local.sh` quits Talkie, builds the signed release app, verifies it, installs it to `/Applications/Talkie.app`, and opens it.

Release settings live in `release/Release.plist`. Entitlements live in `release/App.entitlements`.
