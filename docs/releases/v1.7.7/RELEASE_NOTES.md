# Taskbar Monitor Enhanced v1.7.7 — interrupted Setup recovery

## Reliability fix
- The v1.7.6 Setup could leave an incomplete updater-owned `.tbme-upgrade/old/<managed-file>.restore` scratch if its own process was terminated mid-rollback. A later update attempt failed with `IOException: file already exists`.
- This build removes **only** known temporary `.restore` scratch files, after the journal owner marker and index have been validated; it then recreates them from the SHA-verified prior managed snapshots.
- Unknown, reparse-point, user-owned, or unrelated files are never erased. Existing rollback guards and preserved user settings remain intact.

## Compatible upgrades
- Same per-user root; SHA-pinned official v1.7.6 predecessor is supported for transactional in-place upgrade. One versioned installer, no duplicate application root.
- Glass with true zero background alpha, red hot CPU/GPU/disk warnings, thresholds, chart readability, themes, and settings are retained.
- Optional signed external PawnIO sensor service remains separate. No new kernel driver is bundled.

## Trust and qualification
- Setup is intentionally unsigned under the existing explicit release waiver. A valid hash/CI is not an independent malware certification.
- Reporter-specific WinRing0 driver attribution in Issue #6 remains open.
- Physical AC-interruption testing is out of the accepted scope and has not been performed.
- This release is a **candidate only** until exact-source build, native upgrade, regression, and public asset gates pass.
