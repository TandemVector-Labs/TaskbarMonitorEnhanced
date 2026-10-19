# Taskbar Monitor Enhanced v1.7.3 — CPU efficiency and verified in-place update

## Changes
- Reordered existing Start/Search native-window geometry filters ahead of expensive Windows process-name enumeration; no layout behavior change intended.
- The separate user-controlled **Glass Mode** ON uses zero-opacity background while metric ink remains visible. OFF restores the saved 1–100% background opacity; Start is pinned to the actual taskbar and never intentionally floated.
- **Glass Mode switch visual repair:** the switch and its On/Off label are separate opaque controls, with no double-painted native text on the thumb. The Display preview no longer overlaps its explanation. All nine Settings pages have a layout-collision regression guard.
- One SHA-pinned Windows Setup updates an existing official v1.7.2 installation **in place**, without uninstalling or creating a second per-user root. Existing official v1.6.0/1.7.0/1.7.1 compatible paths remain guarded.

## Verification and scope
- On one owner Windows PC, actual 4 × 60-second BASE–TRIAL–TRIAL–BASE whole-program CPU observation measured 23.37809% versus 6.65184% of one logical core (71.547% lower in those tested conditions), exact prior v1.7.2 Main restored.
- The owner's quiescent 442-file data-root ZIP passed SHA checks and byte-exact isolated restore; this does not establish physical AC power-loss resilience or restore a deliberately damaged owner HKCU registry.
- Candidate verification (Commit `690cef8d6883e7811913a394343fa0e304ccb87a`): independent Windows A/B protected v1.7.2 → v1.7.3 in-place upgrades, journal rollback, idempotence, downgrade refusal and four native Start/Settings/fullscreen/presentation modes passed; standard Build and Verification, exact binary/SBOM, and nine-page no-overlap UI suite passed. Public promotion requires equivalent merged-main exact-head CI, asset provenance and uploaded SHA-256 acceptance.
- The installer is **unsigned** by maintainer choice. Unknown publisher/SmartScreen messages are not proof of malware; actual antivirus detections must not be bypassed or dismissed. External vulnerable-driver issue #6 attribution remains unresolved, as do formal signed labs, physical power loss, and machine-wide multiuser/HKLM collision proof.
- Public immutable v1.7.2 assets are not altered by this new release.
