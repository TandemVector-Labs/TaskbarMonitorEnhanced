# Taskbar Monitor Enhanced v1.7.4 — fresh-install maintenance and protected upgrades

## Fix
- Prevent the redundant root-level TaskbarMonitorEnhanced.cs file during fresh install while retaining the canonical Source/TaskbarMonitorEnhanced.cs file. This resolves the genuine fresh v1.7.3 same-version maintenance defect, independently reproduced on Windows 2025 and 2022.
- Include SHA-pinned official v1.7.3 as a supported source for same-root v1.7.4 in-place upgrade, regardless of whether it was installed fresh (redundant root source present) or upgraded from v1.7.2 (root source absent). Any present legacy root source must match the official SHA before managed removal.
- Glass transparency, separate On/Off switch status label, protected user config and backup, native taskbar geometry and CPU optimizations remain as accepted in v1.7.3.

## Release gates and scope
- Do not release until exact code head builds reproducibly with its own verification tests and two independent fresh Windows instances cover actual fresh 1.7.4 install/maintenance, official v1.7.3 fresh and upgraded to 1.7.4, native Start/Settings/Glass/fullscreen and protected user canaries with rollback.
- The public v1.7.3 release remains immutable; no silent binary replacement and no duplicate per-user installed root.
- Intentionally unsigned; SmartScreen reputation is distinct from antivirus vulnerability detection. Microsoft vulnerable WinRing0 Issue #6 attribution is unresolved. Never disable Defender, bypass quarantines or claim malware-free status. Physical power cut, HKLM multiple-user and external signing/lab are not accepted merely from these CI tests.
