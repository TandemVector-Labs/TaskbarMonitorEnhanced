# Taskbar Monitor Enhanced v1.7.6 — glass thermal warning hotfix

## Bugfix
- On user-enabled fully transparent Glass mode, retain the red thermal warning text, chart and card border when a valid CPU, GPU or disk temperature meets the configured threshold.
- Normal metric glyphs remain theme-adaptive and visible, while background alpha stays 0%. No new driver or sensor dependency.

## Notification behavior
- Thermal highlight and Windows notification balloons are separate features. In Settings > Alerts, enable **Show Windows notification when a threshold is crossed** for notifications; previously disabled preferences are preserved.
- Existing default alert thresholds CPU/GPU 85°C, disk 60°C, hysteresis and cooldown remain unchanged.
- No audible OS notification is promised when Windows Do Not Disturb or notification policies mute alerts.

## In-place update
- Same canonical per-user installation root and existing SHA-pinned previous releases supported; v1.7.5 added as an exact 22-file + signed-off Setup SHA ancestor.
- Keep config, config.bak, history, user assets and HKCU autostart. Journal and recover interrupted upgrades; no forced process termination, no duplicate root.
- v1.7.5's cross-user privileged task safety guard retained. No claim of machinewide singleton or physical AC outage recovery.
- Intentionally unsigned under established waiver. Defender WinRing0 Issue #6 remains open and unrelated to this visual bugfix.

## Verification
- Exact source build and 49 × 2 pixel warning proof plus hosted Windows full CI; real v1.7.5 -> v1.7.6 install/rollback on two disposable Windows required before publication and owner's update.
