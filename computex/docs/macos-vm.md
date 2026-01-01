# macOS VM architecture

This document describes the macOS VM host/guest architecture for Computex.

## Goals

- Run Codex core inside a macOS VM (Apple Silicon only).
- Stream all agent output (model stream, tool calls, stdout/stderr, events, images) to the host UI.
- Allow a persistent primary VM plus disposable per-session clones.

## Host app responsibilities

- Download the latest macOS restore image (IPSW).
- Install and cache a base VM after first-boot user setup.
- Create and manage VM sessions (primary or disposable clones).
- Render the VM display at 1280x720.
- Broker host/guest IPC and surface logs/events to the UI.

## Building the host app (no Xcode)

From `macos-app/`:

```bash
./scripts/build.sh
```

This produces a signed app bundle at `macos-app/dist/ComputexHost.app`.

## Guest responsibilities

- Run Codex core and tools inside the VM.
- Emit all events to the host via the IPC bridge.
- Accept tool calls for screenshots and input from the host.

## Session model

- Base VM: one-time install + user setup, stored as a reusable template.
- Base readiness: user completes setup, then marks the base VM ready for cloning.
- Primary session: a persistent clone reused across launches.
- Disposable sessions: short-lived clones for each task, cleaned up on exit.

## IPC transport (planned)

- Unix domain socket or vsock backed by virtio for host/guest communication.
- JSON line protocol with a `type` field and payload data.
- All events are streamed to the host, including model stream, tool calls/results, stdout/stderr, and screenshots.
