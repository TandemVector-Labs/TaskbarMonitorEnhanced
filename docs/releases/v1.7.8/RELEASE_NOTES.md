# Taskbar Monitor Enhanced v1.7.8 — optional audible thermal warning

## Temperature warnings

- Adds an opt-in **Play Windows warning sound** option under Settings > Alerts.
  New installations and upgrades default to **sound off**, unless you explicitly
  enable it. The existing Windows temperature notification preference remains
  separate and unchanged.
- When both Windows notifications and the sound option are enabled, a real
  CPU/GPU/disk temperature crossing requests Windows' current Exclamation sound.
  The existing per-device transition latch, 3 C hysteresis, ten-minute cooldown
  and user quiet hours/snooze continue to apply: no repeated sound every poll.
- **Test warning sound** in the same Settings page previews the Windows sound
  once on a deliberate click, without heating the CPU or moving thresholds.
- Uses the user's Windows sound scheme and system output volume. Sound can be
  muted/disabled by Windows, so a request log is not evidence a speaker was heard.
  The existing glass zero-alpha background and red hot-temperature text/charts
  are unchanged.

## Existing safe upgrade
- One intentionally unsigned Setup, same per-user installation root.
  Exact SHA-pinned official v1.7.7 predecessor is supported transactionally,
  including the previously verified crash recovery of updater-owned .restore.
- Preserves user config/history/autorun, GPU/disk sensor services, and all
  existing themes, settings, focus and Start/fullscreen handling.
- No new driver; external signed PawnIO policy remains distinct from Setup.
- Physical AC-mains-loss testing is excluded by the owner; global machinewide
  singleton and independent security signing-lab claims are not made.
- Original reporter-specific WinRing0 SHA/download origin remains pending in
  GitHub Issue #6. Never disable or bypass Defender.

## Status and evidence
- This is a private release candidate until hosted Build, GUI/sound-policy
  selftest, fresh/in-place installation, native recovery, supply-chain G16
  and real owner acceptance succeed on exact source.
