# Computex Host (macOS)

This is the macOS host app that runs the macOS VM and shows the UI.

## Requirements

- Apple Silicon Mac
- macOS 14+ (Virtualization.framework)
- Xcode 15+ for signing and entitlements

## Build (local, no Xcode)

Requirements:

- Xcode Command Line Tools (`xcode-select --install`)
- Apple Silicon Mac on macOS 14+

Build + sign an app bundle:

```bash
./scripts/build.sh
```

Run the app:

```bash
./scripts/run.sh
```

You can override the bundle ID:

```bash
BUNDLE_ID=com.yourorg.computex.host ./scripts/build.sh
```

## Debugging (with logs)

`swift run` does not apply the virtualization entitlement, so the restore-image catalog can fail to load.
For debugging with stdout logs, use:

```bash
./scripts/dev-run.sh
```

## Behavior

- On first launch, the app downloads the latest macOS restore image (IPSW) and installs a base VM.
- The first boot is user-driven so macOS setup can complete.
- After setup, click "Mark Base Ready" to cache the base VM. You can resume the primary session or clone a disposable VM per session.
- Restore images and settings are persisted under `~/Library/Application Support/Computex/VMs/`.
- Checkpoints (state + cloned disk) live under `~/Library/Application Support/Computex/VMs/Sessions/<id>.vm/Checkpoints/`.

## Notes

- Default resources: 2 CPU cores, 4 GB RAM. Advanced overrides are planned.
- The VM display is fixed to 1280x720 for tool coordinate mapping.
