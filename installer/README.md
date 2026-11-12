# Installer source

This folder contains the custom Windows installer source used by Taskbar Monitor Enhanced.

## Current public authority

The current immutable official stable version is **v1.7.9**, published from exact source commit `479ee78a214c7ae58177016d59468e50e815f54b`. The single intentionally unsigned per-user Setup is available on [GitHub Releases](https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/tag/v1.7.9). Verify SHA-256 `3AE5E2AC7428C3443FF7768C543117AF864E7C73F68D32EFAD4AB40B30FB5B0E`. Official PawnIO is a separately licensed optional external dependency and is not bundled.

## Protected sensor baseline

The historical v1.7.0 candidate introduced the R21 process-isolated architecture, Broker protocol 1.1.2+r21 and Sensor Supervisor 1.3.0+r33. Sensor reuse remains gated by exact payload hashes and live health. A missing optional PawnIO dependency degrades protected temperatures rather than triggering an unexpected driver download or installation.

Installer behavior includes:

- non-elevated main application
- elevation only for the protected hardware-sensor layer
- independent CPU, GPU and storage sensor workers
- supervisor health validation across all protected-sensor worker lanes
- Scheduled Task restart policy limited to three retries
- MultipleInstances=IgnoreNew
- fail-closed drain of prior sensor processes before replacement
- stale split-telemetry cleanup during upgrade
- pinned LibreHardwareMonitor 0.9.6 and optional external PawnIO 2.2.0 provenance (the official PawnIO binary is NOT bundled in the OSS Setup)
- embedded source/license/attribution closure
- setup /verify resource gate requiring 25 OSS resources with PawnIOBundled=false, including TaskbarMonitorEnhanced.exe.config

The authoritative reproducible build path is ../build/Build.ps1.

PawnIO is intentionally retained on uninstall because other hardware-monitoring apps may depend on it. Existing PawnIO >=2.2.0 is reused; otherwise protected sensors safely degrade. Users explicitly install the optional official PawnIO driver from https://github.com/namazso/PawnIO.Setup/releases/tag/2.2.0; Setup does not silently download it.

For the current official release, refer to the immutable v1.7.9 GitHub Release Manifest, SHA256SUMS, Release Notes and public tracker Issue #7. Historical acceptance documents (including v1.6.0) remain available but are not the current release authority.
