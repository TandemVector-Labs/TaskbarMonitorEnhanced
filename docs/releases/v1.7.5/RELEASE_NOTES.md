# Taskbar Monitor Enhanced v1.7.5 — cross-user sensor-layer safety

## Critical fix
- Prevent one Windows account's elevated sensor setup/uninstall from unregistering the machinewide sensor Scheduled Task, terminating sensors, or removing shared Program Files sensor payload owned by a different account.
- Before any shared mutation resolve the target SID, verify the existing task principal and all observable broker/supervisor process owners; on foreign or unknown ownership, fail closed and leave protected sensors unchanged, while allowing the current user's main app and independent settings to work with unavailable protected readings if necessary.
- Fresh no-task installs and same-account repairs remain permitted. This is a safety guard, **not** global single-install enforcement, task per-SID migration, or permission to disable antivirus.

## Installer and delivery
- Single 64-bit Windows per-user Setup; exact SHA-pinned immutable official v1.7.4 22 managed rows supported for same-root v1.7.5 update with atomic rollback. Existing v1.6–v1.7.3 official upgrade sources retained.
- Preserves Glass alpha-zero mode, separate On/Off state label, Start/Settings/fullscreen, user's config/previous backup, startup registration and uninstaller state.
- Intentionally unsigned under prior publisher waiver. Microsoft genuine vulnerable-driver WinRing0 Issue #6 attribution awaits the reporter's exact driver SHA/install source and independent review. Physical AC power loss and cross-account actual full protected-sensor cohabitation are not claimed.
- Release only after exact merged source Build/metadata/security/rollback and independent two-host Windows A/B official v1.7.4→v1.7.5 and fresh install maintenance tests; verify and redownload all 7 public artifacts before owner in-place upgrade.
