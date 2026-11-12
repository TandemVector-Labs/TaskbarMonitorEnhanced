# Taskbar Monitor Enhanced v1.7.10 - UNRELEASED R299 candidate

Maintenance security hardening: replaced the prior mutable Temp batch-file
uninstall cleanup with a parent-identity-checked, canonical-owner-root and SID
checked, native handle-pinned deferred deletion. Native reparse and external
canary protections have passed independent hosted Windows tests (R298).

This candidate adds SHA-pinned official public v1.7.9 as an accepted in-place
upgrade predecessor, authenticating Main and Setup plus 22 product-managed files
against the immutable v1.7.9 published Setup resource manifest. Superseded
release notes are removed only within the rollbackable managed-file transaction.

**Not yet released.** Upgrade/rollback, failure-injection, portable runtime,
CI, provenance and owner Start/Settings acceptance gates are distinct.
The official v1.7.9 Release remains immutable and independently available.
