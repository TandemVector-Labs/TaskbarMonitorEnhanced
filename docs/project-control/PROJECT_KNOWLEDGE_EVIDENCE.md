# Project Knowledge / Evidence Record — Taskbar Monitor Enhanced
<!-- TBME:PUBLIC-KNOWLEDGE:R287 -->
## 2026-10-17 / R286–R287 — v1.7.8 owner real thermal sound API (public redacted scope)

- [Release v1.7.8](https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/tag/v1.7.8) source 9960a06dba606d1c93b8ca2b84e0e3e25ca4f68d, Setup SHA 4DB3C03AC7AB70B3D3123A365C156E71370F0338991B399B99169A4B5B5F8B75, Main SHA A3E9ABD7E97655AD6787B71239505F30A7C0350B77F352DE4DE83461CD170D31, seven immutable assets. Build 38977412946 (27/27) and native Windows two-host crash recovery 38977412933 (3/3) PASS; a real same-root per-user update and protected 26-file previous-version archive were verified, with Glass zero alpha/hot red retained.
- The new optional sound setting defaults off for fresh installations; the owner enabled it. Settings includes a manual one-shot Test warning sound. Natural CPU high temperature warnings then produced 26 paired Windows Exclamation sound API requests, zero logged failures and minimum spacing 10.001 min, using existing quiet-hours, 3C hysteresis and ten-minute cooldown. OS Exclamation sound file exists. A request log is not proof physical speaker audibility or a visible Windows balloon.
- Reporter-specific WinRing0 original file SHA/download origin remains missing in Issue #6. Unmerged PR #80 has CodeQL path-analysis warnings still needing exact Windows/security adjudication. Separate signed local PawnIO on a different PC cannot clear the reporter. No Defender bypass. User excluded actual AC power-loss tests, and accepted one per-user unsigned Setup rather than a global machinewide singleton.

<!-- TBME:PUBLIC-KNOWLEDGE:R285 -->
## 2026-10-17 / R285 — release and owner verification public summary (redacted derivative)

- Versioned crash fix: private/native Windows-hosted actual v1.7.6 Setup interruption exposed a stuck updater-owned .restore scratch; R284 v1.7.7 reconstructs only owned scratch after journal/index validation. PR #76 merged dc68cf448173bd0808d1dfa54bc9e9bf7ca20aad; exact-main Build CI 38965519302 and Windows A/B crash recovery CI 38965519445 PASS. Real physical power cut was excluded by owner.
- Public immutable seven-asset v1.7.7 GitHub release ID 415382091, Setup SHA 395AEE56006F55FD5DCCFB52E1519088CE01A10386840D7008C6BA900136A06D, Main SHA A6D4BFD00C918C0601A12D185F414E92F2B6A85927042B811537B0BC37606253; independent artifact G16 PASS. Official v1.7.6 retained unchanged.
- Real owner same-root one-per-user v1.7.6→v1.7.7 upgrade Exit 0; 26 original managed/protected files archived, all five shipped build outputs matched, config and Glass zero-alpha preserved, one Main/one Supervisor/two Brokers, no second HKLM install. Actual CPU 95C app notification dispatch logged; OS audio/banner not independently heard or seen.
- Outstanding external items only: original reporter WinRing0 file SHA/source (Issue #6) and actual owner-app OS alert presentation/audio observation. Global machinewide singleton and signed-publisher attestation are explicitly outside accepted per-user unsigned scope; do not disable Defender.



## 2026-09-26 — R22 final identity/build/install/runtime acceptance

- Context: derive exact public v1.1.2 from accepted RC10 without behavioral drift.
- Claim/Decision: final identity behavior/build inputs are equivalent to accepted RC10 after approved identity-only normalization.
- Evidence/Source: docs/acceptance/R22_FINAL_IDENTITY_EQUIVALENCE.json; 7/7 covered; PASS.
- Confidence/Status: Confirmed / PASS.
- Reuse Targets: release notes, audit, Project Brain, future regression baseline.

- Claim/Decision: exact final build is deterministic and supply-chain evidence is complete locally.
- Evidence/Source: docs/acceptance/archive/v1.1.2/FINAL_BUILD_ACCEPTANCE.json, docs/releases/archive/v1.1.2/RELEASE_MANIFEST.json, docs/releases/archive/v1.1.2/SHA256SUMS.txt, R21_SBOM.spdx.json.
- Confidence/Status: Confirmed / PASS.
- Provenance: source commit 5916db0ef7fe19fea8cc13ebde73d01021d7c3d6.

- Claim/Decision: exact final v1.1.2 is installed and accepted on the validation workstation.
- Evidence/Source: r21_evidence/R22_FINAL_INSTALLED_IDENTITY.json SHA256 0528164956E250A4D112407FFA3BBC1EF880BA7A39D59356762C5C444537532D; Main/Broker/Supervisor exact hash match; config preserved; sensor log READY.
- Confidence/Status: Confirmed / PASS.
- Reuse Targets: release manifest, GitHub release evidence, final report.

- Claim/Decision: proportional final runtime regression is PASS; heavy RC10 watchdog/S3 gates are inherited rather than rerun because final behavior equivalence is PASS.
- Evidence/Source: r21_evidence/R22_FINAL_RUNTIME_REGRESSION_R2.json SHA256 7F53FEF9BCFD81D5B7862CB30DAFAAF7F659937013D6EA895AB89182023C30D7 plus accepted RC10 precursor.
- Confidence/Status: Confirmed / PASS.
- Limitation: final local runtime validation is on the current Windows 11 validation workstation; it is not a claim of all-hardware compatibility.

- Failure/Root Cause/Prevention: first final-runtime harness reported StateAgeSec about 12600 s while every structural/health flag passed. ConvertFrom-Json had materialized trailing-Z JSON timestamps as DateTime; reparsing through a string/local path introduced the workstation +03:30 offset. Prevention is PowerShell 7.5+ ConvertFrom-Json -DateKind String followed by round-trip DateTimeOffset parsing.
- Method Source: Microsoft Learn ConvertFrom-Json documentation for PowerShell 7.5/7.6, DateKind String and trailing-Z UTC behavior.
- Confidence/Status: Confirmed harness false negative / prevention regression PASS.
- Reuse Targets: all future JSON timestamp harnesses in this project.

- Open Gate: GitHub provenance/SBOM attestation and immutable v1.1.2 Stable/Latest publication remain PENDING. No public-release PASS is claimed yet.

## 2026-09-26 — GitHub run 36244394685 shallow-checkout failure

- Date/Context: first exact-final GitHub attestation push at control commit 483367af265eae8bd6043c11570f8f6be58531de.
- Claim/Decision: failure is in CI checkout depth, not in product build/runtime.
- Evidence/Source: GitHub job 108410742894; Checkout and .NET setup succeeded; Git whitespace check failed because HEAD^ was unavailable; build/determinism/SBOM/attestation/upload were skipped.
- Root Cause: r21-ci.yml used actions/checkout default fetch-depth 1 but executed git diff --check HEAD^.
- External Method Evidence: official actions/checkout v7 documentation prescribes fetch-depth: 2 for HEAD^; action input documentation states default fetch-depth is 1.
- Prevention/Guard: add only fetch-depth: 2 to the pinned Checkout step; fetch-depth 0 is unnecessary.
- Regression: fresh exact-commit run; require every CI step PASS and artifact hashes equal accepted final hashes.
- Confidence/Status: Confirmed root cause / fix applied / regression pending.
- Reuse Targets: CI design, release audit, Project Brain, future workflow review.

## 2026-09-26 — GitHub exact-final attestation and artifact equivalence

- Date/Context: release/v1.1.2-final, fresh GitHub run 36244774522 at commit aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0.
- Claim/Decision: GitHub CI and supply-chain attestation are accepted for the exact release authority commit.
- Evidence/Source: GitHub job 108411834610 success; all required build/determinism/SPDX/provenance/Setup-SBOM/upload steps succeeded; artifact 10907450490 digest sha256:09cd3846e054007b736be16ffee4c9865de923526940ae474b43d20bdf099dd6.
- Artifact verification: Main, Broker, Supervisor and Setup SHA256 values are byte-identical to the locally accepted finals.
- SBOM result: raw GitHub SPDX SHA256 1C3D36B725BAC33A61BE9D886C4C6AA6E78ECAE58D5815DDA13E4F68229B1B9B differs from local B324745F6041FA8E8C8FA888977B40B41100B787C6A8E087ED80EB23AC148578. Generator audit proved the volatile fields are documentNamespace from Git HEAD and creationInfo.created from build-manifest time. Normalizing only those fields yields identical BFBB7FB00FF3C8DD9ED26DBD17C0E3CAED5B4F666BE5373E7C329549AEEB7BAA.
- Decision rationale: release tag will target aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0, the exact GitHub-attested commit. Subsequent documentation/control commits must not move the immutable tag.
- Initial failure: run 36244394685 failed before build because checkout depth 1 could not resolve HEAD^. Prevention: pinned checkout retained, fetch-depth 2 added, fresh run 36244774522 PASS.
- Confidence/Status: Confirmed / PASS / publication-ready.
- Reuse Targets: public release notes, release manifest, audit report, Project Brain, future CI/release design.
- Limitation: runtime acceptance is on the validated Windows 11 workstation and is not a claim of universal hardware compatibility.
## 2026-09-26 — v1.1.2 immutable public release accepted

- Date/Context: final publication and post-verification of Taskbar Monitor Enhanced v1.1.2.
- Claim/Decision: v1.1.2 is the accepted immutable public Stable/Latest release.
- Evidence/Source: tag v1.1.2 resolves to aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0; release https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/tag/v1.1.2 is non-draft/non-prerelease; default latest release is v1.1.2.
- Asset verification: 8/8 assets uploaded; GitHub asset digest equals local SHA256 for every asset; GitHub size equals local size for every asset.
- Setup artifact: SHA256 25744A0A0F78B787A5FC3601577748B80353ADC9DAFB9FE91A111A53C56216FB.
- Release evidence SHA256: E1E87345C6AC430420DBE56FF7B5150BA4ED71AE0E4380919F41D11334DE95FC.
- Authority model: behavior/build authority is 5916db0ef7fe19fea8cc13ebde73d01021d7c3d6; immutable release/tag authority is aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0; branch closeout may advance but must never move tag v1.1.2.
- CI lesson: shallow checkout failure was prevented with minimum sufficient fetch-depth 2 because the workflow uses HEAD^; fresh exact-commit CI subsequently passed.
- SBOM lesson: compare document-instance fields separately from substantive package/file/dependency payload when generator intentionally embeds commit/time; normalized semantic equivalence was PASS.
- Confidence/Status: Confirmed / PASS / FINAL.
- Reuse Targets: future release checklist, CI design, audit/report, user-facing verification instructions.
- Limitation: runtime acceptance applies to the validated Windows 11 workstation; universal hardware compatibility remains outside this release claim.
## 2026-09-26 — development Authenticode signing identity and pipeline

- Context: post-v1.1.2 maintenance. Immutable public v1.1.2 must not be modified because Authenticode changes executable bytes/hashes.
- Identity: self-signed DEVELOPMENT Code Signing certificate, subject CN=Taskbar Monitor Enhanced Development Code Signing, thumbprint 4673165CCB579F868EFE5F52FCDA761780F49989, RSA/sha256RSA, Code Signing EKU 1.3.6.1.5.5.7.3.3.
- Security handling: private key remains in Cert:\CurrentUser\My, was not exported, and no PFX/P12/PVK/KEY material exists in project files. Only the public .cer is committed.
- Tooling: build/signing/Sign-Authenticode.ps1 uses Windows SDK signtool with SHA256 and optional RFC3161 timestamping; Verify-Authenticode.ps1 validates signed state, signer thumbprint, hash integrity and trust state.
- Probe evidence: unsigned Setup copy hash 25744A0A0F78B787A5FC3601577748B80353ADC9DAFB9FE91A111A53C56216FB; signed DEVELOPMENT probe hash 65168AD41EAA0C5B562FACE9E3DDEBACDA9EBC38606C94C42D4E9C55AA6AAFCD.
- Verification: exact signer thumbprint matched; unsigned file rejected; tampered signed copy rejected.
- Trust interpretation: Get-AuthenticodeSignature returns UnknownError with message that the chain terminates in an untrusted root. This is the expected result for the self-signed development certificate and is not public Publisher trust.
- Immutability regression: public tag v1.1.2 remains aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0 and release Setup digest remains sha256:25744a0a0f78b787a5fc3601577748b80353adc9dafb9fe91a111a53c56216fb.
- Production gate: obtain CA-issued Code Signing certificate or approved managed signing identity; sign/timestamp a NEW release version; then regenerate signed hashes, SBOM, provenance and runtime acceptance.
- Confidence/Status: Confirmed / DEVELOPMENT SIGNING PIPELINE PASS / PUBLIC TRUST PENDING.

## 2026-09-26 — R24 SignPath Foundation public-trust readiness

- Context: user authorized full completion of public code signing after the R23 self-signed development Authenticode pipeline passed.
- Provider research: SignPath Foundation publishes a free open-source signing route with repository ownership, OSI-approved licensing, maintained/released documentation, visible Code signing policy, privacy/uninstall disclosure, MFA, author/reviewer/approver roles, manual approval, and verifiable source-built artifacts. Microsoft Artifact Signing is geographically restricted and therefore was not treated as the universal primary route.
- Repository evidence: GitHub repository is public; maintainer account `GOD13emad` reports two-factor authentication enabled.
- License correction: root LICENSE had only a short notice while README/CONTRIBUTING already declared GPL v3-or-later. It was replaced with the already-accepted full GNU GPL v3 license text from local project evidence; declared license family remains GPL-3.0-or-later.
- Policy/readiness docs: README, CODE_SIGNING.md, DOWNLOAD.md and PRIVACY.md now describe the current immutable v1.1.2 baseline, exact SignPath provider attribution, team roles, manual signing approval, source/build provenance gates, privacy/update behavior and uninstall route without claiming external acceptance.
- Actual updater evidence: default auto-check uses HTTPS GET to `https://api.github.com/repos/GOD13emad/TaskbarMonitorEnhanced/releases/latest`; setting can disable automatic checks; installer download occurs only after explicit Download & Install confirmation and hash/release checks.
- Actual PE metadata evidence: Main, Broker, Supervisor and Setup all PASS ProductName `Taskbar Monitor Enhanced`, ProductVersion `1.1.2+r21`, FileVersion `1.1.2.0`, populated CompanyName and FileDescription. Their hashes remain the accepted final hashes.
- Actual uninstall evidence: installer creates `%LOCALAPPDATA%\TaskbarMonitorEnhanced\Uninstall.exe` and registers DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString and QuietUninstallString in the per-user Windows uninstall key. README/DOWNLOAD expose Windows Installed apps and direct uninstaller instructions.
- Application surface evidence: official SignPath apply page is a HubSpot embedded form using portal `145110231` and form `bf62807d-bb72-4e45-9bde-1f3a53ba2472`; page loaded in Chrome and Tagline/Description fields were visibly observed.
- Submission gate: browser input was rejected by Remote Commander with `WORKFLOW_GUI_TAKEOVER_REQUIRES_DIRECT_USER_SESSION`. This is an enforced platform interaction gate; chat authorization cannot override it. Application is therefore NOT SUBMITTED.
- Ready packet: `docs/security/SIGNPATH_APPLICATION_PACKET.json` status `READY_TO_SUBMIT_DIRECT_USER_GUI_ACTION_REQUIRED`, with main-branch policy/privacy URLs, verified GitHub 2FA fact, product metadata PASS, uninstall PASS, form identifiers and submitted=false.
- Immutability: v1.1.2 tag remains `aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0`; Setup SHA256 remains `25744A0A0F78B787A5FC3601577748B80353ADC9DAFB9FE91A111A53C56216FB`.
- Confidence/Status: Repository readiness Confirmed/PASS; external SignPath application submission BLOCKED by direct-user GUI gate; SignPath Foundation acceptance/public trust PENDING.
- Prevention: never substitute self-signed trust, install a development root to manufacture a PASS, rewrite immutable v1.1.2, or invent/accept external identity/legal fields. Public signing must start on a new release after external provider acceptance.

## 2026-09-26 — R24 default-branch publication and CI

- Readiness authority: commit `b6c13838624e99d1d6ba4811b295834e22e45947`.
- Default branch prestate: `main` at `ce657da44cb68590c73fafb4030a0abddb428685`; ancestry check proved it was an ancestor of the readiness authority.
- Mutation: ordinary non-force fast-forward `git push origin HEAD:main`; poststate `origin/main` and `origin/maintenance/signpath-readiness` both equal `b6c13838624e99d1d6ba4811b295834e22e45947`.
- GitHub Actions run `36250864888` at exact head SHA `b6c13838624e99d1d6ba4811b295834e22e45947`: completed success.
- CI evidence: every step in job `build` succeeded, including reproducible build, deterministic clean-clone verification, SPDX 2.3 SBOM, binary provenance attestation, Setup SBOM attestation and evidence upload.
- Release immutability remained PASS after main publication: tag `v1.1.2` -> `aab35e5e0e3420f3b21e8febe49bc9e2cc8bb8c0`; public Setup digest remains `sha256:25744a0a0f78b787a5fc3601577748b80353adc9dafb9fe91a111a53c56216fb`.
- Decision: repository-side prerequisites for SignPath Foundation application are accepted. This is not provider acceptance and not a public-trust signature.
- External gate: official SignPath HubSpot application is loaded but Remote Commander input is blocked by `WORKFLOW_GUI_TAKEOVER_REQUIRES_DIRECT_USER_SESSION`; application remains NOT SUBMITTED.
- Confidence/Status: Confirmed / repository readiness PASS / default branch PASS / CI PASS / external provider submission PENDING direct-user GUI action.

## 2026-09-26 — SignPath exact form schema and final human gate

- Official application page: `https://signpath.org/apply.html`.
- HubSpot form: EU1 portal `145110231`, form `bf62807d-bb72-4e45-9bde-1f3a53ba2472`.
- Public render definition: `https://forms-eu1.hsforms.com/embed/v4/render-definition/145110231/bf62807d-bb72-4e45-9bde-1f3a53ba2472`; SHA256 `bf122cf482f6887667fb30661e3be8bafdcdac0c15c05c5a79a72f5337aeb570`.
- Required factual fields: Project Name, Repository URL, Homepage URL, Tagline, Description, Reputation, Build System, First Name, Last Name, Email, Primary Discovery Channel.
- Optional factual fields: Download URL, Privacy Policy URL, Wikipedia URL, Maintainer Type, Company Name, exact discovery source.
- Prepared factual values are stored in `docs/security/SIGNPATH_APPLICATION_PACKET.json`.
- Reputation measurement for Taskbar Monitor Enhanced at observation time: 0 GitHub stars, 0 forks, 0 subscribers, 0 v1.1.2 asset downloads. The application must not imply established adoption.
- Declared GPL upstream `leandrosa81/taskbar-monitor`: 540 stars, 42 forks, 13 subscribers. These values are upstream heritage only, not adoption metrics for Taskbar Monitor Enhanced.
- Required external consent #1: agreement to SignPath Foundation Code of Conduct and understanding that certificates are issued in SignPath Foundation's name and can be revoked if terms are violated.
- Required external consent #2: agreement to allow SignPath to store/process personal data.
- Optional marketing communication checkbox is not authorized and remains unchecked.
- reCAPTCHA2 is present and is a human anti-bot gate. Programmatic solution or bypass is forbidden.
- User explicitly authorized mouse/keyboard for this current task. Plugin permission is already Allow all actions. However, this ChatGPT session's exposed `gui_session_begin` contract only accepts `ttlSeconds` and returns observe mode; takeover parameters used by the server's newer contract are absent. Workflow GUI takeover is independently rejected with `WORKFLOW_GUI_TAKEOVER_REQUIRES_DIRECT_USER_SESSION`.
- The official application and Code of Conduct pages have been opened on the desktop and the application page was reopened last.
- Security boundary: no raw local MCP, Windows SendInput, UIAutomation, CDP or equivalent injection is used to bypass the connector's takeover gate; no CAPTCHA bypass is attempted.
- Status: repository readiness PASS; application payload READY; submission NOT SUBMITTED; explicit first-person consents + reCAPTCHA remain the only legitimate human gates.

## 2026-09-27 — v1.1.3 startup resilience and visual requalification

- Observed failure mechanism: `StartWithWindows=true` was present in config and StartupApproved was enabled, but the actual HKCU Run registration for Main was missing after a real power-loss/restart cycle. Sensor Supervisor still launched independently. Cause of the Run-value deletion is not proven.
- Prevention architecture: retain HKCU Run as primary launch and add a current-user Startup-folder shortcut as a privilege-independent recovery path. Recovery uses `--startup-recovery`, waits up to 12 seconds for the primary process, exits early on primary detection, otherwise starts normally. Existing mutex prevents duplicate long-running Main instances.
- A Scheduled Task fallback was considered but rejected after non-elevated creation of an ONLOGON task returned Access Denied on the validation PC.
- Mutual self-heal is live-proven in both directions. StartWithWindows=false removes both registrations and original true state was restored after the negative test.
- Candidate code/visual authority: commit `bcbd8f8e8861e4e4a83350699214f1bb83b1132e`.
- Main v1.1.3 hash: `74E7725E3C3911EFEDEC1181C21AF07571C9A22CD758EE50E06EA1373DAB7317`.
- Setup v1.1.3 hash: `159D6995D16A549DAC35BD6EF69543A63D6675778C37012619BEFDABFD43598C`.
- Existing protected Broker/Supervisor hashes remain `182D634616434AECADD3A9AF54A746BB61FD70EC0F788DC12429679AA197D833` and `38553CCE30D5D3F1A22AC6765C4A0F5D4D204970A3DAD7BA9467A326235FC196`; sensor layer remains 1.1.2+r21 / READY.
- Deterministic clean-clone build at the candidate commit: PASS. SPDX 2.3 SBOM SHA256 `651057410EB57090E1D7ED5EB9522AB8B40284D484CAB0A1C9ADA4DC1833E192`.
- Theme proof: PASS, 14/14 themes, 30 live samples, no synthetic metrics. Compact proof: PASS for 592 and 500 px, zero recorded overflow. Theme/compact manifests and contact sheets are now repository documentation.
- v1.1.2 immutability regression remains PASS: tag `aab35e5e...`, Setup `25744A0A...`.
- Public trust: no SignPath/CA signature is claimed. Repository readiness and application preparation are separate from actual provider acceptance.
- Status: Confirmed / LOCAL ACCEPTANCE PASS / GitHub CI and immutable publication pending.

## 2026-09-27 — v1.1.3 public release evidence

- Public release `v1.1.3` is accepted at exact tag commit `fa8c75d0b59343ccb7eae86320a351e3b4064c48` and is GitHub Latest.
- Two exact-head GitHub Actions runs passed: main `36311195266` and release branch `36311191121`. Downloaded CI Main/Broker/Supervisor/Setup binaries matched local accepted hashes exactly.
- Release upload integrity is 7/7 exact by GitHub asset digest and size. Installer SHA256 is `159D6995D16A549DAC35BD6EF69543A63D6675778C37012619BEFDABFD43598C`; source ZIP SHA256 is `D6B3B99AEEE7B3E816D94ECE6C41F25FDF338833923AFB08A3A4B29907F227CA`.
- The published local SPDX document and exact-head CI SPDX document have different raw hashes because their generated namespace/time fields differ; normalized semantic content (packages, file hashes, relationships and document identity fields excluding generated namespace/time) is identical with SHA256 `2e5375bfa63263162953f2c2a7a8c98b7cc4729bbb871cc7aad9f90b3c4238a1`. Treat exact-head CI attestation as source-origin evidence and the published SBOM as release-asset inventory evidence.
- Startup-resilience fault injection and all-theme/compact proof remain accepted. Protected sensor binaries are unchanged from accepted `1.1.2+r21`.
- v1.1.3 remains unsigned for public-trust purposes unless an independently verifiable trusted Authenticode signature is later proven; do not infer signing from SignPath readiness.
- v1.1.2 remains immutable and unchanged.
- Reuse target: future release checklist, startup regression suite, public-release post-verification, SBOM raw-vs-semantic equivalence handling.

## 2026-09-27 — GitHub Actions upload-artifact Node 24 maintenance

- Official actions/upload-artifact v7.0.1 resolves to commit `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` and declares `using: node24`.
- The repository's previous pin `ea165f8d65b6e75b540449e92b4886f43607fa02` triggered a GitHub deprecation annotation because it declared Node.js 20, although GitHub forced execution under Node.js 24 and CI passed.
- Maintenance changes only `.github/workflows/r21-ci.yml`; v1.1.3 release bytes/tag are intentionally untouched.
- Validation pending exact-main workflow at the time of this entry.

### Validation result

- Commit `1fabcfc420fa996cc2e7e44a4182d2569ddba007` → GitHub Actions run `36311950294`: SUCCESS.
- All R21 gates passed and the earlier Node.js 20 deprecation annotation did not recur.
- Decision: retain `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (v7.0.1, Node.js 24) as the current pinned upload action.


## 2026-09-27 — repository hygiene / deduplication rules

- Keep one canonical Git source workspace. Use short-lived worktrees only when needed, then remove them after evidence is committed/preserved.
- Keep immutable public release history in Git tags + GitHub Releases; merged audit/release/maintenance branches should not be kept indefinitely.
- Do not keep superseded draft RC releases after a stable release is accepted.
- Preserve irreplaceable hardware/runtime evidence by moving it to a single external archive; delete rebuildable output and duplicate runner/download stores.
- Keep dependency caches centrally and reuse them through an ignored local junction rather than downloading the same pinned binaries repeatedly.
- Pinned dependency hashes must be verified whenever a central cache is reattached.
- Historical unmerged branches with unique commits should not be deleted merely for cosmetic cleanup; preserve until their lineage is intentionally reconciled or archived.
- Release tags/assets remain immutable during repository cleanup.


### R26 validation result

- Repository-hygiene commit `f671bb4aee4dadc2f418e95c21471faa108322e7` passed GitHub Actions run `36313319634`.
- Central dependency-cache reuse was proven locally with no download; final Setup binary hash remained identical to the accepted v1.1.3 hash.
- After cleanup, only local `main` remains; remote unmerged historical lineage is preserved rather than destructively deleted.
- Superseded RC draft releases and branch-specific RC self-hosted workflows were removed from active GitHub surfaces.


## 2026-09-27 — GitHub README blank-image root cause

- `docs/screenshots/desktops/desktop-dark-minimal.webp` was not merely a browser/GitHub loading issue. The stored WebP was truncated: RIFF-declared total size 62,952 bytes vs actual Git object size 15,008 bytes.
- A broken media file can cause GitHub README to leave a large empty render area even when the Markdown path itself exists.
- Professional handling: remove invalid media, stop describing it as evidence, replace it with verified renderer output, and structurally validate all remaining media/link targets.
- Historical RC manifests/checksums should be preserved outside repository root under an explicit acceptance/archive path rather than deleted when they remain useful for auditability.


## 2026-09-27 — professional repository information architecture

- Public repository roots should contain current project entry points and standard policy files, not every historical release artifact.
- Version belongs primarily in directory hierarchy for archived records; filenames inside version directories should remain generic where practical.
- Preserve Git history with `git mv` rather than delete/recreate when reorganizing accepted evidence.
- Keep immutable historical JSON evidence semantically intact even if its physical repository path changes; document archive location externally instead of rewriting fields that describe the original release state.
- Project-control knowledge is documentation and belongs under `docs/project-control/`, not in a special root folder once the project is public and stabilized.


## 2026-09-27 — immutable installer docs vs mutable public README

- If an installer embeds the repository README, post-release documentation edits can silently produce a different installer with the same public version even when executable code is unchanged.
- Prevention: freeze release-embedded documentation as a version-scoped payload snapshot and let the public landing-page README evolve independently.
- For v1.1.3, the accepted embedded README resource was extracted directly from the immutable published Setup and stored as `docs/releases/v1.1.3/INSTALLER_README.txt`; the build maps it back to payload logical name `README.md`.
- This restored exact Setup reproducibility while allowing GitHub presentation cleanup.
- Active tooling should use stable generic names (`Build.ps1`, `ci.yml`, `BUILD_MANIFEST.json`, `SBOM.spdx.json`); release/revision identifiers belong in manifest content and historical evidence rather than active filenames.


### Repository-structure cleanup validation

- Commit `80f9c95afbc419bf49384d16be6f9a63d09a05d4` passed exact-head GitHub Actions run `36315722461`.
- CI `build-evidence` artifact id `10929984813` used generic current filenames and reproduced the immutable v1.1.3 Setup hash exactly.
- GitHub API verification confirmed the public root, docs top level, workflow list, and build directory no longer expose obsolete release-candidate/versioned artifact filenames as active files.
- Decision: use version directories + generic filenames for historical records, and stable generic filenames for active tooling; keep revision/version identifiers inside immutable evidence or manifest content only when technically meaningful.


## 2026-09-27 — final public-tree cleanup rule

- For a stabilized public repository, do not duplicate every historical release/RC artifact on current `main`; immutable tags, Git history, GitHub Releases, and an external evidence archive are sufficient historical authorities.
- Before deleting historical tracked records from the active branch, preserve a hashed external copy when local audit continuity matters.
- Keep current-release evidence in version directories with generic filenames; keep active tooling filenames version-neutral.
- Public docs should link to GitHub Releases/tags for old versions rather than retaining local archive trees that clutter browsing.
- Validation after structural cleanup must include link integrity, deterministic build, exact installer hash regression, and exact-head CI.


### Final cleanup validation

- `ce94e70a170abdfeb6b5c4491c9cebd7d029639c` passed GitHub Actions run `36317306947`.
- Active main no longer carries historical archive trees or old RC/revision/versioned artifact filenames.
- Historical unmerged branch lineage was preserved in a verified complete Git bundle before branch deletion; bundle SHA256 is `736C13A830F6440D8BF972A39556798D0028ABE1442F739AA00E4FDFD3F18948`.
- Remote branch policy after stabilization: retain only `main`; preserve exceptional unmerged history externally before deleting stale public branches.


## 2026-09-27 — v1.2.0 modern Settings / hover guard / 28-theme candidate

### Record A — Settings-open hover flyout root cause and prevention
- Date/Context: 2026-09-27, user reported that hover explanations/details open while Settings is visible and remain open.
- Claim/Decision: CONFIRMED root cause is an interaction-state gap: opening Settings stopped the hover watchdog timer, while overlay MouseEnter/MouseMove continued to invoke the flyout-opening path.
- Evidence/Source: source audit of `OverlayForm.OpenSettings`, `HandleHardwareHover`, `HoverWatchdog`; deterministic `--hoverguardproof` result `PASS MOVE_SUPPRESSED=TRUE WATCHDOG_SUPPRESSED=TRUE FLYOUT_HIDDEN=TRUE`.
- Prevention: guard both hover resolution and watchdog when Settings exists; hide active flyout and reset hover identity state. Preserve regression CLI.
- Confidence/Status: CONFIRMED / PASS.
- Reuse Targets: maintenance regression, release acceptance, future hover/flyout changes.
- Provenance: `src/TaskbarMonitorEnhanced.cs`; candidate source SHA256 after identity update `83653DB76846C10A62C030961A0CB5295ECADE34B46327935B08459941BC4EF4`.

### Record B — Settings architecture choice
- Date/Context: 2026-09-27, professional/modern Settings redesign.
- Claim/Decision: preserve WinForms and the accepted runtime/sensor architecture; modernize presentation using a left navigation shell, page header/descriptions, constrained content, grouped surfaces, consistent spacing/controls, and persistent actions.
- Method evidence: Microsoft Windows app settings guidance recommends simple grouped settings, readable constrained-width layouts and SettingsCard-style header/description/action composition; Microsoft NavigationView guidance supports clear left navigation with a page header and consistent content margins.
- Sources:
  - https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings
  - https://learn.microsoft.com/en-us/windows/apps/design/controls/navigationview
  - https://learn.microsoft.com/en-us/windows/apps/design/basics/navigation-basics
- Trade-off: no WinUI migration. This avoids a new framework/deployment dependency and regression surface while delivering the requested UX within the existing proven desktop architecture.
- Confidence/Status: CONFIRMED design choice / visual proof PASS 8 pages.
- Reuse Targets: UI design rationale, release notes, maintenance.
- Provenance: `--settingsproof`; evidence root `C:\Users\Aa.Emad\source\archives\TaskbarMonitorEnhanced\2026-09-27_v1.2.0-candidate-evidence\settings`; manifest SHA256 `5163A4D6CE85500A959DA8A72081CA8A67B993A4B8DDE52E18DE55E5BD2A588A`.

### Record C — visual-proof false-positive failure and guard
- Date/Context: 2026-09-27 during Settings visual qualification.
- Failure: initial Settings proof reported output files but screenshots were blank because the Form had only been CreateControl-initialized and never entered a real shown/painted WinForms state.
- Root Cause: artifact existence was incorrectly treated as rendering evidence.
- Prevention/Guard: proof harness now shows the form off-screen, pumps Windows messages/layout/paint, captures after rendering, and visual review remains required for representative pages.
- Regression: all 8 current Settings pages render nonblank after the harness correction.
- Confidence/Status: CONFIRMED failure → prevention implemented.
- Reuse Targets: all future GUI screenshot/proof harnesses.

### Record D — tooltip/flyout behavior benchmark
- Method evidence: Microsoft documents that hover tooltips disappear when pointer/focus stops hovering and advises using tooltips sparingly for supplemental information.
- Source: https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/tooltips
- Decision: a Settings-open flyout that stays open is not accepted behavior; suppression while a modal/configuration experience is active is the minimum sufficient control.
- Confidence/Status: CONFIRMED method basis.

### Record E — 28-theme renderer architecture
- Date/Context: 2026-09-27, request to roughly double theme count with high quality and meaningful differentiation.
- Claim/Decision: expand from 14 to 28 themes using seven reusable renderer families plus distinct palettes, rather than adding 14 near-duplicate custom renderers.
- New families: aurora, luxe, zen, synth, matrix, paper, industrial.
- Benefit/Trade-off: visually distinct geometry/background language with bounded code growth and shared regression paths.
- Evidence: live-data ThemeProof 28/28; compact 592/500 proof; representative visual review across every new renderer family.
- Theme manifest: `6791C6C44CA3FC7B547282E87864D7EF564BC70A02CAAB5C78A605533F47C304`.
- Compact manifest: `0D6DEB7547BD218A96A5E264C12F2FFCF692E24453EE75BF3F8C7367D7928138`; 252 layout checks, 0 overflow.
- Confidence/Status: CONFIRMED / PASS for renderer and layout proof.
- Reuse Targets: release gallery, theme documentation, regression suite.
- Provenance: `C:\Users\Aa.Emad\source\archives\TaskbarMonitorEnhanced\2026-09-27_v1.2.0-candidate-evidence`.

### Record F — release identity boundary
- Decision: use `v1.2.0` candidate identity because the scope adds substantial user-facing UI/theme capability; never rebuild or retag immutable public v1.1.3 as if it contained these changes.
- Candidate: `1.2.0 / V1_2_0_R01_MODERN_SETTINGS_THEME_LIBRARY / 1.2.0+r01`.
- Sensor layer: unchanged `1.1.2+r21`.
- Current status: local build/visual/functional proof PASS; clean-clone determinism, candidate SBOM, live installed-main validation and exact-head GitHub CI remain open at this record point.
- Confidence/Status: CONFIRMED boundary / publication NOT YET ACCEPTED.
- Reuse Targets: release engineering and provenance.


## 2026-09-27 — installed v1.2.0 identity and gallery acceptance

### Record G — installed candidate identity
- Claim: installed Main and Uninstaller exactly match the locally qualified v1.2.0 candidate.
- Evidence: Main SHA256 `B90211E86AAF0AB05C3B87E2D2056A59B2D6369FCAD0ADCC8072A513FCB489D9`; Uninstall/Setup SHA256 `3196986C62FC7D9A91500B0E3246D5640E6292D0ED1722F736505A4DD511B3CF`; registry DisplayVersion `1.2.0`.
- Sensor state: READY, `1.1.2+r21`, exact Broker/Supervisor hashes preserved.
- Runtime evidence: health probe PASS, resilience STABLE, CPU/GPU/storage transport and data available.
- Confidence/Status: CONFIRMED / installed technical validation PASS.
- Reuse Targets: final acceptance, release notes, support diagnostics.
- Provenance: `%LOCALAPPDATA%\TaskbarMonitorEnhanced\install_state.json`, uninstall registry, installed binary hashes.

### Record H — GUI interaction boundary
- Observation: Remote Commander provided screenshot observation but rejected direct mouse interaction with `GUI_TAKEOVER_NOT_AUTHORIZED`.
- Decision: do not bypass connector policy using alternate input injection.
- Validation substitute: real WinForms Settings form is shown off-screen and painted before deterministic capture; all 8 pages reviewed. Installed `--hoverguardproof` directly validates the reported Settings-open flyout failure path.
- Status: foreground manual mouse UAT MISSING by tool authority; automated UI/behavior evidence PASS.
- Reuse Targets: final report and release-risk statement.

### Record I — current gallery/public documentation
- Evidence: `docs/screenshots/themes` now contains 28 full-width live-data theme proofs + manifest/contact sheet; `docs/screenshots/compact` contains 56 592/500px proofs + manifest/contact sheets; `docs/screenshots/settings` contains 8 Settings proofs + manifest/contact sheet.
- Visual review: PASS for representative and contact-sheet inspection.
- Markdown link audit: 38 files, 0 broken relative links.
- Decision: current README/DOWNLOAD/release/acceptance docs distinguish v1.2.0 candidate from immutable public v1.1.3 until exact-head CI/publication completes.
- Confidence/Status: CONFIRMED / documentation ready for CI gate.


### Record J — translated release-status false-claim prevention
- Date/Context: 2026-09-27, pre-PR repository audit.
- Observation: 11 i18n README files changed together to candidate 1.2.0/28 themes, but their validation sentence also changed from historical 1.0.0 lifecycle validation to an unsupported v1.2.0 lifecycle claim.
- Decision: do not accept the unsupported upgrade/full-uninstall/clean-install claim for v1.2.0.
- Evidence boundary: v1.2.0 currently has local full build, deterministic rebuild, visual proofs, installed identity/runtime health and preserved protected-sensor evidence; exact-head GitHub CI/publication remain open at this record point.
- Prevention: translated status text now explicitly distinguishes source candidate 1.2.0 from public release v1.1.3 and names only proven v1.2.0 gates.
- Confidence/Status: CONFIRMED / false claim removed before PR.
- Reuse Targets: release documentation, localization maintenance, evidence-boundary reviews.
- Provenance: `docs/i18n/README.{ar,bn,es,fa,fr,hi,id,pt,ru,ur,zh-CN}.md`; pre-commit diff audit.

## 2026-09-27 — v1.2.0 public publication closure

### Record K — immutable public release authority
- Date/Context: 2026-09-27 final publication after PR and main exact-head CI.
- Claim: v1.2.0 is the current public immutable Latest release.
- Evidence: GitHub release id `397665644`; tag `v1.2.0`; annotated tag object `5f4c12c2dd8ee2624e93d31ff8672894f5701311`; peeled commit `84d22fae6638b21683ea828e86517d100ced1654`; published `2026-09-27T13:45:13Z`; state non-draft, non-prerelease, immutable, Latest.
- Public URL: `https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/tag/v1.2.0`.
- Confidence/Status: CONFIRMED / FINAL_PUBLIC_RELEASE_ACCEPTED.
- Reuse Targets: current authority, updater/release documentation, support, provenance.

### Record L — release asset digest closure
- Pre-publication staging contained exactly seven release assets.
- Setup pre-publication resource verify: PASS 19/19.
- `SHA256SUMS_v1.2.0.txt`: 6/6 referenced assets matched before upload.
- Draft GitHub release comparison: 7 local assets vs 7 remote assets; 0 missing; 0 extra; 0 size/digest mismatches.
- Post-publication GitHub audit: all seven assets remain state=uploaded with the same digests.
- Setup: `3196986c62fc7d9a91500b0e3246d5640e6292d0ed1722f736505a4dd511b3cf`.
- Source ZIP: `d5996a44ceb991dde019f00592128596dcadf555d0e4c4217c873699e08f5ee9`.
- SHA256SUMS: `d2f5aa6ba345081f2977959c522bb206d801543689bcb82b99d129b086a3ab16`.
- Release manifest: `2f3f7c8e001092c8cf5e439ba18dbd62a740e024a75c2d0c81379e20e47a54bd`.
- SBOM: `09e38d790aea054ecde580eba3515f285fe72f05758384f83a46d1b181a5a8ec`.
- Acceptance asset: `833f67a9ca7a236197353b34481e0c1004a75dfc3f98843a8628ef728ff52d86`.
- Release notes asset: `02ed6e71802ca0fdc819693ea713a6a02af234443257dcbe6f0fc156d2256822`.
- Confidence/Status: CONFIRMED / PASS_7_OF_7.
- Provenance: external staging root `C:\Users\Aa.Emad\source\archives\TaskbarMonitorEnhanced\2026-09-27_v1.2.0-publication\assets` and GitHub release asset digests.

### Record M — exact-main CI equivalence without artifact re-download
- Main run `36322557793` on exact release commit `84d22fae6638b21683ea828e86517d100ced1654` completed SUCCESS.
- CI passed reproducible build, clean-clone determinism, SPDX generation, binary provenance attestation, Setup SBOM attestation and evidence upload.
- GitHub job log printed the authoritative build manifest and confirmed exact equality of all four binary hashes with local/release values.
- A direct CI artifact ZIP download was attempted but stalled on the PC network and wrote no bytes. After bounded observation it was terminated; no blind retry loop was used.
- Decision: artifact download is not a necessary additional gate once authoritative CI log manifest + provenance/SBOM attestation + local deterministic build establish the same binary hashes.
- Confidence/Status: CONFIRMED / minimum-sufficient release evidence satisfied.
- Reuse Targets: future release process under constrained network conditions.

### Record N — post-publication immutability rule
- Decision: do not edit `docs/releases/v1.2.0/RELEASE_NOTES.md` or `docs/releases/v1.2.0/INSTALLER_README.txt` after publication because they are release payload/build inputs.
- Rationale: changing embedded release payload text after publication can change rebuilt Setup bytes and break release reproducibility/immutability.
- Current public status updates belong in public indexes, acceptance, Brain/Knowledge and current README/DOWNLOAD files instead.
- Confidence/Status: CONFIRMED preventive control.
- Reuse Targets: all future immutable releases.

### Record O — merged feature-branch preservation and cleanup
- Date/Context: 2026-09-27, after immutable v1.2.0 publication.
- Risk: squash merge means the feature branch tip is not a direct ancestor of main; deleting it without an independent record would reduce convenient recoverability of intermediate commits.
- Prevention: create and verify a complete Git bundle before branch deletion.
- Bundle: `C:\Users\Aa.Emad\source\archives\TaskbarMonitorEnhanced\2026-09-27_v1.2.0-publication\feature-modern-settings-theme-library.bundle`.
- Bundled tip: `2e3f953b402e2b512096fcd59533184739127f91`.
- SHA256: `E13DC2AC746F85D6B64B28B3CB7099A1EF5244EBFCD16E991A817FAAC1A87E66`.
- Verification: `git bundle verify` PASS / complete history.
- Remote and local feature branch deletion then completed and absence was verified.
- Confidence/Status: CONFIRMED / PASS.
- Reuse Targets: repository hygiene, account transfer, historical recovery.

### Record P — post-publication exact-head regression and final repository invariant
- Date/Context: 2026-09-27, final repository closeout after v1.2.0 publication.
- Post-publication documentation commit: `60db90069c8eae74cddcb5d953db1f99adab1229`.
- Exact-head GitHub Actions run: `36324665609` = SUCCESS.
- Reproducible build, deterministic clean-clone, SPDX generation, binary provenance attestation and Setup SBOM attestation all passed.
- Printed CI manifest reproduced the exact immutable v1.2.0 binary hashes for Main/Broker/Supervisor/Setup.
- Release invariant audit: `v1.2.0` remains public, non-draft, non-prerelease, immutable and Latest with seven assets; tag still peels to `84d22fae6638b21683ea828e86517d100ced1654`.
- Repository invariant audit: remote branch surface contains only `main`; local worktree was clean at audit time.
- Conclusion: documentation closeout did not perturb release binaries or immutable release authority.
- Confidence/Status: CONFIRMED / PASS / FINAL.
- Reuse Targets: future release baseline, regression authority, repository maintenance.

## R32 Deep-PC Audit Knowledge Delta - 2026-10-01

### K-R32-01 - Canonical-root consolidation without breaking operational ownership

Status: CONFIRMED.

- Project-owned inactive history/evidence should physically live under the canonical project root, but live installed runtime, OS integration objects, external application caches, cross-project evidence, and global tool backups must not be moved merely for neatness.
- Correct pattern: inventory -> source hash manifest -> classify ownership -> MOVE only inactive TBME-owned content -> COPY cross-project/global-tool evidence -> SNAPSHOT live runtime/integration -> post-operation full re-hash.
- R32 Phase 1 verified 2,049/2,049 files and Phase 2 verified 8,601/8,601 files with zero SHA-256 mismatches.
- A compatibility junction can preserve historical absolute paths after physical archive consolidation, but it must be documented so future scans do not count it as a second physical authority.

Prevention rule: never equate "everything belongs in root" with moving Windows operational files. Canonical knowledge can be complete while live deployment remains at required OS paths.

### K-R32-02 - Whole-machine discovery must distinguish accessible volumes from drive letters

Status: CONFIRMED.

- C:, D:, and H: were mounted/readable and recursively scanned.
- F: existed as a PowerShell drive letter but Test-Path F:\ was false with no mounted media.
- Initial scan: 6,039 project-related matches. Post-consolidation scan outside root: 315 classified matches, D:=0.
- Remaining matches were entirely explained by live runtime, shortcuts, external cache, global backup/cross-system evidence, and KISH_AI mirrors.

Prevention rule: a drive-letter enumeration is not proof of a readable volume; record mount/readability before claiming full-machine coverage.

### K-R32-03 - Shallow repositories can invalidate project-origin conclusions

Status: CONFIRMED.

- The local Git repository was shallow at audit start. Treating the earliest visible commit as project origin would have been false.
- git fetch --unshallow origin --tags --prune restored full public history and v1.1.2 tag.
- git fsck then exposed two dangling commits and two dangling blobs.
- Dangling commits were preserved in a verified bundle and blobs were exported before any possible cleanup. No git gc/prune was run.
- Legacy packages further proved that the actual enhanced project predates public Git: R9R3 on 2026-08-15 references R8 and contains the PowerShell runtime.

Prevention rule: before historical conclusions, check git rev-parse --is-shallow-repository, fetch complete ancestry if safe, run fsck, and preserve unreachable evidence before cleanup.

### K-R32-04 - Storage one-shot success contract can produce false degradation

Status: CONFIRMED current defect; root-cause mechanism HIGH-CONFIDENCE.

Evidence:
- Supervisor storage timeout is fixed at 12 seconds.
- Supervisor accepts storage success only after the one-shot process exits and then validates the output file.
- Broker writes valid storage output and logs BROKER_ONCE_PASS after ReadStorage / AtomicWrite / Computer.Close, yet several attempts near the timeout boundary are still classified TIMEOUT by Supervisor.
- Observed one-shot durations grew from sub-second/low-seconds to approximately 10-12 seconds; some attempts later did not log PASS before the Supervisor kill.
- Valid SSD telemetry for all three installed SSDs was present, but Supervisor backoff made current storage transport/data unavailable and health probe DEGRADED.

Inference:
- Disk discovery is not the primary problem.
- The contract couples valid data acceptance too tightly to worker process termination and a budget too close to real teardown/exit latency. Post-Main/managed/native teardown or lingering threads can keep the worker alive after useful data is available.

Prevention/design rule:
1. Validate freshness/schema of output independently from process-exit timing.
2. Define timeout from measured latency percentiles plus bounded margin, not a single optimistic constant.
3. Reap/kill a lingering worker after accepting valid output only if lifecycle safety is proven.
4. Record elapsed read/write/close/exit stages separately.
5. Add deterministic slow-exit, delayed-close, valid-output-before-exit, timeout/backoff, and recovery regression tests.
6. Never label fresh validated data unavailable solely because exit acknowledgement missed a narrow polling window.

### K-R32-05 - Native GPU faults must be interpreted with driver-transition chronology

Status: CONFIRMED chronology; causal attribution remains UNPROVEN.

- One isolated SensorBroker crash occurred on 2026-09-30 at 14:56:55 with AccessViolationException in LibreHardwareMonitor NvidiaML.NvmlDeviceGetPowerUsage / nvml.dll.
- Windows UserPnp events at 14:56:53-14:56:54 show NVIDIA display services being re-added for the same RTX 3080 immediately before the crash.
- The faulting NVML was 8.17.16.1656; current NVML is 8.17.16.1714 and the old DriverStore version is gone.
- The GPU worker recovered to READY within seconds; Main stayed alive. Event-log audit from v1.2.0 publication through R32 found no second TBME application crash.

Prevention rule: correlate native telemetry crashes with driver/PnP transitions before blaming routine steady-state code. Keep native hardware access isolated, add driver-transition testing, and preserve bounded recovery/backoff.

### K-R32-06 - Startup self-heal is startup-scoped, not continuous

Status: CONFIRMED.

- At R32 start, config StartWithWindows=true and recovery shortcut were valid while the primary HKCU Run registration was absent.
- Current startup log had no STARTUP_RUN error, so the actor that removed the Run value is UNPROVEN.
- StartupManager.SetEnabled repairs primary Run and recovery shortcut only after a new primary instance crosses the mutex path.
- Recovery invocation returns early when another Main is already running, before SetEnabled.
- Therefore deletion after startup can leave redundancy degraded for the rest of the session.
- R32 preserved prestate, removed orphan predecessor taskbar-monitor StartupApproved residue, restored exact primary Run value, and verified poststate PASS.

Prevention rule: if StartWithWindows is enabled, verify both registration channels periodically or on a bounded maintenance trigger, with tests for deletion after the application is already running.

### K-R32-07 - Audit harness failures are evidence failures, not product failures

Status: CONFIRMED.

Observed:
- Full-drive synchronous search exceeded transport limits; solution was a background terminal plus persisted inventory.
- A consolidation verifier failed on desktop.ini due item-resolution behavior after the move. State was audited first, then verification was repaired; mutation was not blindly repeated.
- The first safe-proof harness returned zero result rows because PowerShell function scope and ArgumentList construction were wrong; zero-byte redirects and absent artifacts made the run INVALID / NOT COUNTED. A ProcessStartInfo.ArgumentList harness then produced 121 artifacts and 8 PASS / 1 genuine health FAIL.
- Hardlink dedup failed on a long path. Transaction rollback left 5,487/5,487 eligible paths present and zero temporary residue.
- LZX compression succeeded, but FileAttributes.Compressed remained unsuitable as a verifier for /EXE:LZX. Windows reported 7,293 compressed files and 2.1:1 ratio; full post-compression SHA-256 verification passed 7,419/7,419.

Prevention rule: validate the verifier itself. A harness with no expected artifacts or an unsuitable OS attribute must not be used to declare product failure. After a mutation failure, inspect state before deciding whether any rerun is safe.

### K-R32-08 - Archive cleanup: preserve semantic paths, remove only proven redundant copies

Status: CONFIRMED.

- Legacy download history is meaningful chronological evidence; widespread hash duplicates may still encode stage/provenance by filename/path.
- Only four explicit copy-suffixed files were deleted after a same-hash canonical counterpart was proven. Broad duplicate deletion was intentionally avoided.
- Ten inactive self-hosted runner trees contained 3.06 GB logical data with heavy duplication. Instead of destructive dedup, NTFS LZX compression preserved every path and byte while freeing about 1.53 GB.

Prevention rule: prefer reversible/transparent storage compression for forensic history over deleting same-content files whose paths may have evidentiary meaning.

### K-R32-09 - Dependency lock is current and reproducible as of audit date

Status: CONFIRMED.

- LibreHardwareMonitor pinned 0.9.6; cached ZIP hash exactly matches lock SHA-256 086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001.
- PawnIO pinned 2.2.0; cached installer hash exactly matches lock SHA-256 1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032.
- Official GitHub latest-release metadata queried from Emad PC reported v0.9.6 and 2.2.0 respectively, both stable/current.

Prevention rule: evaluate a dependency update because of a concrete defect or new upstream release, not merely because a native fault occurred during a driver transition.

### K-R32-10 - Release acceptance and current runtime health are different authorities

Status: CONFIRMED.

- v1.2.0 release acceptance remains immutable evidence of what passed at publication.
- R32 current health proof is DEGRADED because the live Storage lane is in timeout/backoff.
- It is incorrect to rewrite historical release acceptance as failed; it is equally incorrect to use historical acceptance to claim current live full-health when new evidence contradicts it.

Prevention rule: always label time-scoped release acceptance separately from current operational health.


## R33 v1.3.0 Release Knowledge Delta - 2026-10-02

### K-R33-01 - Separate valid sensor data acceptance from worker-exit acknowledgement

Status: CONFIRMED / RELEASED.

- A one-shot native worker can produce fresh valid output before managed/native teardown completes. Treating process exit as part of the data-validity contract created false Storage degradation in R32.
- v1.3.0 validates fresh Storage output independently, uses a 20 s no-valid-output timeout, then a 3 s exit grace and bounded reap.
- Final live soak on Emad-PC-Ultimate: 73 samples, five new Storage attempts, zero failure samples, zero consecutive failures, maximum completion 292 ms, final HEALTHY_DATA.

Prevention rule: data freshness/schema and lifecycle completion are separate contracts. Do not discard validated telemetry solely because process termination acknowledgement is late.

### K-R33-02 - Startup redundancy requires bounded continuous maintenance

Status: CONFIRMED / RELEASED.

- Startup-only repair leaves a same-session gap if an external actor removes HKCU Run or corrupts the recovery shortcut after Main is already running.
- v1.3.0 verifies both channels every 60 s only while StartWithWindows is enabled and repairs only observed mismatches.
- Final-hash live fault injection: primary Run repaired in 16.1 s; recovery shortcut repaired in 30.1 s; no fallback restore; target/arguments/working-directory contract passed.

Prevention rule: if a redundant startup channel is part of availability design, verify it periodically or on another bounded maintenance trigger, not only at process bootstrap.

### K-R33-03 - Protocol compatibility and Supervisor build identity must be distinct

Status: CONFIRMED / RELEASED.

- The Broker protocol remains `1.1.2+r21`, but R33 materially changed Sensor Supervisor behavior. Keeping the Supervisor binary labelled 1.1.2+r21 would obscure deployment evidence and could make reuse semantics ambiguous.
- v1.3.0 exposes `SupervisorVersion=1.3.0+r33` separately from `BrokerVersion=1.1.2+r21` and requires both plus exact payload hashes/live health for sensor reuse.
- Final reinstall recorded `SensorLayerMode=CURRENT_EXACT_R33` and did not restart the already-correct sensor processes.

Prevention rule: never reuse one version string for both protocol compatibility and a materially changed implementation binary.

### K-R33-04 - Support bundles and reset tools need explicit privacy/rollback contracts

Status: CONFIRMED / RELEASED.

- Support ZIP is user initiated and local. Its manifest must not reveal machine name or absolute user-profile source paths merely for diagnostics convenience.
- Safe Defaults must create a recoverable config copy before loading defaults and must not mutate the running monitor until Save & Apply.
- v1.3.0 self-tests privacy-manifest absence and duplicate-timestamp backup uniqueness/preservation.

Prevention rule: diagnostics export should follow minimum-necessary metadata; destructive-looking UI actions must have a separately testable rollback/preservation contract.

### K-R33-05 - Public release authority is an exact commit + binary hashes + published digests

Status: CONFIRMED / FINAL.

- v1.3.0 annotated tag object `8d9314a60ceaaa074b5f877aaf4d224337780fb3` peels to `fc5619d049de4a95cb23542a8c3318e12f064691`.
- Release-branch CI `36980484008` and main CI `36980902415` succeeded and printed exact 4/4 release binary hashes.
- GitHub Release id `401629671` is immutable, non-draft, non-prerelease and Latest with 7/7 asset digest matches.
- Trusted Authenticode remains an external gate and is not inferred from repository-side release quality.

Prevention rule: never promote a release from version labels alone; tie authority to tag/commit, reproducible hashes, CI, runtime acceptance, release-asset digests and explicit signing state.


### K-R33-06 - Close merged temporary branches only after immutable release authority exists

Status: CONFIRMED / PASS.

- Both temporary R33 branches pointed to release commit `fc5619d049de4a95cb23542a8c3318e12f064691`, which was proven ancestor of `main` before deletion.
- The annotated `v1.3.0` tag and immutable GitHub Release already preserved the release authority.
- After branch deletion, the remote branch surface contains only `main`; no release history was lost.

Prevention rule: branch cleanup is housekeeping, not release authority. Delete only after merge/ancestor proof and after immutable tag/release evidence exists.


### K-R34-01 - Theme previews must reuse the production renderer

Status: CONFIRMED / RELEASED.

- A palette swatch is not an accurate preview of a theme whose identity includes card geometry, font treatment, graphs, compact behavior and metric layout.
- v1.3.1 removed the synthetic palette preview and routes Settings through the same `PaintBackground -> BuildMetricViews -> PaintMetric` pipeline used by the live taskbar monitor.
- The runtime preview uses the active Overlay snapshot and sparkline history; proof mode gathers 12 live samples with no synthetic data.
- Off-screen preview rendering must not mutate the live Overlay window size. Width is supplied as an explicit layout input.

Prevention rule: visual configuration previews must share the production renderer or a tested shared rendering primitive; do not maintain a second hand-drawn approximation.


## R35 v1.4.0 Knowledge Delta - 2026-10-02

### K-R35-01 - DPI authority must be explicit and shipped with the executable

Status: CONFIRMED / RELEASED.

- WinForms DPI behavior is runtime configuration, not merely a source-level intention.
- v1.4.0 deploys `TaskbarMonitorEnhanced.exe.config` with PerMonitorV2 and High-DPI auto-resizing, tracks it in deterministic build output, build manifest, CI artifact and dedicated provenance attestation.
- Installed runtime config hash exactly matches build/CI authority.

Prevention rule: treat runtime configuration that changes Windows behavior as a first-class release artifact with reproducibility and provenance evidence.

### K-R35-02 - Accessibility acceptance needs machine-verifiable UI metadata and system-color behavior

Status: CONFIRMED / RELEASED.

- v1.4.0 Settings proof checks 67 interactive controls with zero missing accessible names and 143 High Contrast controls with zero style gaps.
- Keyboard navigation shortcuts are part of the product contract, not a documentation-only claim.
- High Contrast resolves through Windows system colors rather than hard-coded theme colors.

Prevention rule: accessibility completion requires testable metadata, keyboard paths and system visual-mode behavior; visual inspection alone is insufficient.

### K-R35-03 - In-app updates require canonical identity and a launch-time integrity recheck

Status: CONFIRMED / RELEASED.

- Digest validation alone is insufficient if release/tag/asset identity can point outside the canonical repository path or if a verified file changes before launch.
- v1.4.0 rejects draft/prerelease, noncanonical tag/release/setup URLs and reparse-point installer paths.
- SHA-256 is recomputed immediately before installer launch.

Prevention rule: update trust is an end-to-end identity + immutability + digest + final-use verification chain, not a one-time download checksum.

### K-R35-04 - Crash diagnostics should be local, bounded and privacy-safe

Status: CONFIRMED / RELEASED.

- v1.4.0 writes a bounded local `last_crash.json` for unhandled exceptions and redacts the user-profile and TBME data-root paths.
- The snapshot is added only to user-initiated Support ZIP exports.
- Feature-contract proof validates crash snapshot privacy.

Prevention rule: diagnostic usefulness does not justify leaking machine/user path metadata; collect minimum necessary local evidence and export only on user action.

### K-R35-05 - Multi-monitor capability and multi-monitor physical validation are different claims

Status: CONFIRMED / RELEASED WITH HOST LIMITATION.

- Selector/placement/recovery code supports discovered secondary Windows taskbars and has deterministic policy tests.
- The current Emad-PC-Ultimate validation session exposed one 3440×1440 monitor and one primary `Shell_TrayWnd`.
- No physical two-monitor attachment proof is claimed.

Prevention rule: separate implementation coverage from environment-dependent physical coverage. Never fabricate a hardware validation result that the current host cannot exercise.


### K-R35-06 - Temporary release branches are disposable only after immutable release authority exists

Status: CONFIRMED / PASS.

- `release/v1.4.0-r35` pointed at exact release commit `924b9bd140b531733c08ca6297d3f8beedc8bb18`.
- Release-branch CI and main CI were both green, the annotated tag and immutable GitHub Release existed, and the release commit was proven an ancestor of main before deletion.
- After cleanup, the remote branch surface is only `main`.

Prevention rule: temporary release branches are transport/control surfaces, not permanent release authority. Delete them only after tag/release immutability and ancestry are proven.


## 2026-10-02 — R36 v1.5.0 candidate: actionable alerts and session export

- Date/Context: post-v1.4.0 benchmark-driven product completion change set.
- Claim/Decision: retain the existing protected sensor layer and implement only high-value Main/UI gaps: actionable temperature notifications, bounded session CSV export, and a Task Manager quick action.
- External method evidence: Microsoft Learn documents WinForms NotifyIcon balloon notifications and BalloonTipClicked on the .NET Framework stack; TrafficMonitor v1.86 continues to invest in taskbar usability/secondary-monitor/localization rather than requiring a plugin architecture for every product increment.
- Decision rationale: reuse the existing NotifyIcon and avoid a Windows App SDK dependency. This is the minimum-sufficient path for native Windows-visible alerts on the current net48 WinForms architecture.
- Implementation: optional notifications are disabled by default; CPU/GPU/disk lanes notify only on a new threshold crossing, require 3 C cooling hysteresis to re-arm, and enforce a 10-minute per-lane cooldown. Clicking the notification opens Alerts settings.
- Implementation: SessionTelemetryHistory is in-memory only, bounded to 3,600 samples, and exports CSV only on explicit user action. It records UTC time, CPU/RAM/GPU, VRAM, disk throughput, network throughput and available temperatures. No cloud upload or persistent telemetry database is added.
- Implementation: taskbar context menu adds Open Task Manager using taskmgr.exe.
- Validation pre-commit: app build PASS with 0 warnings / 0 errors; --selftest PASS; --feature-contract-selftest PASS; full Build.ps1 -NoDownload PASS including Setup 1.5.0, setup verification, canonical payload and sensor windowless PE gates.
- Failure/Root Cause/Prevention: first determinism attempt failed because Verify-Determinism.ps1 clones committed Git HEAD while R36 was still uncommitted. The clone correctly built v1.4.0, so comparison against uncommitted v1.5.0 outputs was invalid. Prevention: run clean-clone determinism only after candidate commit; do not treat this as a product determinism failure.
- Confidence/Status: implementation Confirmed; pre-commit build/tests PASS; exact-commit determinism, runtime install regression, CI and publication PENDING.
- Reuse Targets: v1.5.0 release notes, audit report, Project Brain, future notification/history design.

- Determinism root cause refinement: after committing R36, Setup alone still mismatched between primary and clean clone. Audit found src/app.manifest was explicitly LF-pinned in .gitattributes while installer/setup.manifest was not. The primary patched manifest was LF; Windows clean clone could materialize CRLF. Because the setup application manifest is embedded into the PE, this can alter Setup bytes while Main/Broker/Supervisor remain identical. Minimum control added: installer/setup.manifest text eol=lf. Regression requires rebuild from exact commit and clean-clone determinism PASS.

- Live-install gate failure: first v1.5.0 quiet install deployed Main hash 94E76E2D7A09BBBA47DC77CBFAAC536A929D1537A912CBF82053E7B2FFC8857F and FileVersion 1.5.0.0 while preserving the existing Supervisor PID, but install_state.json was rewritten with Version/PublicVersion 1.4.0. Root cause: two stale hardcoded 1.4.0 strings in SetupProgram.WriteInstallState. Fix is limited to those two fields; update-manager 1.4.0 URLs remain intentional test fixtures. Regression requires rebuild, determinism and reinstall with install_state Version/PublicVersion 1.5.0 plus unchanged protected sensor identity.


## 2026-10-02 — R36 local acceptance complete; GitHub promotion gate opened

- Candidate build head audited: 3a7d9668f735e86c30d60ff3626dfd9f8e9a30b7.
- Exact-head Build.ps1 -NoDownload: PASS, all four projects 0 warnings / 0 errors; setup 1.5.0, canonical payload and windowless sensor PE gates PASS.
- Exact-head clean-clone determinism: PASS after fixing installer/setup.manifest EOL policy.
- Candidate proof suite: 11/11 PASS (selftest, feature contracts, Settings, theme, compact, hover, startup, health, shell, hardware, temperature).
- Live upgrade evidence: v1.4.0 -> v1.5.0; protected Supervisor PID preserved across upgrade; installed state reports CURRENT_EXACT_R33 and correct v1.5.0 identity.
- Postinstall/installed acceptance: 11/11 PASS; installed Main/config/Broker/Supervisor/Uninstaller hashes match current BUILD_MANIFEST 5/5.
- Config migration preservation: PASS. Comparing current config against backup while excluding the intended migration fields ConfigSchemaVersion and EnableTemperatureNotifications produced zero other semantic differences; schema=6 and new notification setting defaults false.
- Final live health evidence: PASS / STABLE, process containment true, CPU/GPU/storage transport and data lanes healthy.
- Candidate acceptance record: docs/acceptance/v1.5.0/CANDIDATE_ACCEPTANCE.json.
- Status: LOCAL_CANDIDATE_ACCEPTED_PENDING_GITHUB_CI. Public release authority remains v1.4.0 until release-branch CI, main CI/provenance and immutable GitHub release verification pass.
- Exact next action: commit local-acceptance records, push release/v1.5.0-r36, require exact-SHA GitHub CI PASS before promotion to main.


## 2026-10-02 — v1.5.0 FINAL PUBLIC RELEASE ACCEPTED

- Final release authority: GitHub Release v1.5.0, release ID 401880404, published 2026-10-02T14:18:41Z.
- Release tag type: lightweight; tag resolves exactly to d952a87fab02fe74046b8d19ae14a2801d6da644.
- GitHub status: Latest=true, Draft=false, Prerelease=false, Immutable=true.
- Release asset gate: PASS 7/7. GitHub-reported asset size and SHA-256 match the locally accepted staging set after publication.
- Public installer SHA-256: 0329d3a49cd1a73dbb95c28f3a22ba6befe65cd65e5c562606c02972392586e1.
- Release-branch CI run 37017612215 and main CI run 37018027405 both succeeded on exact SHA d952a87fab02fe74046b8d19ae14a2801d6da644, including reproducible build, clean-clone determinism, SPDX SBOM, binary provenance, runtime-config provenance, Setup SBOM attestation, and artifact upload.
- Runtime acceptance retained: candidate 11/11 PASS, postinstall/installed 11/11 PASS, installed artifact equality 5/5, config migration semantic preservation PASS, final protected-sensor health PASS/STABLE.
- Protected sensor layer remains unchanged: Broker protocol 1.1.2+r21 and Supervisor 1.3.0+r33.
- Public-trust Authenticode remains UNSIGNED_PENDING_EXTERNAL_PROVIDER; no trusted-signature claim is made.
- Previous public authority v1.4.0 remains immutable historical authority; it was not overwritten.
- Final public acceptance record: docs/acceptance/v1.5.0/PUBLIC_RELEASE_ACCEPTANCE.json.
- Release assets: Setup, source ZIP from exact release SHA, release notes, SPDX SBOM, candidate/publication acceptance asset, release manifest, and SHA256SUMS.
- Root-cause prevention carried forward: installer/setup.manifest is explicitly LF-pinned to preserve Setup determinism across Windows clean clones.
- Reuse Targets: release auditing, future updater verification, next-version baseline, article/report/thesis provenance.

## 2026-10-02 — R37 v1.6.0 Performance Workspace & Theme Studio local candidate

- Fact/Confirmed: R37 adds a seven-page Performance Workspace and 20 original Studio renderer themes, increasing the built-in catalog to 48.
- Fact/Confirmed: Config schema advances to 7. New traffic retention is opt-in/off by default; no cloud telemetry or background upload is introduced.
- Fact/Confirmed: protected sensor implementation is unchanged at Broker 1.1.2+r21 and Supervisor 1.3.0+r33.
- Verification: full authoritative build operation b8afdb36-1026-43b0-afd2-d68da9263b91 PASS with zero warnings/errors for Main/Broker/Supervisor/Setup, sensor PE PASS, canonical payload PASS, setup 24-resource verify PASS and reproducible-build PASS.
- Validation: corrected fresh regression operation 14a4c0cc-4d73-440c-9c54-412b03d530fa PASS 15/15 with real child-process exit codes. 48 theme images, 7 Workspace pages, 96 compact images and 9 Settings pages physically exist. Theme manifest reports 30 live samples and no synthetic metric data.
- Live host result: shell/start/hardware/temperature/health/support proofs PASS; health reports STABLE, R21 process containment true and CPU/GPU/Storage data available.
- Failure R37-F1: proof harness omitted PrepareProofProcesses; root cause proof-only helper omission; fixed and compile regression PASS.
- Failure R37-F2: generated Build.ps1 used malformed Join-Path expressions for four new source resources; fixed to direct canonical paths; full Build.ps1 regression PASS.
- Failure R37-F3: an intermediate regression wrapper used null Trim and then PowerShell automatic $args, creating unreliable/invalid summary behavior. That claimed PASS is superseded and MUST NOT be used. Fresh regression3 with null-safe $arguments ran for the full proof duration and is the accepted local regression authority.
- Status: LOCAL CANDIDATE PASS; clean-clone determinism, exact-head CI, live upgrade/installed-runtime and immutable publication remain open gates.
- Exact next action: commit exact candidate, rebuild exact commit and run clean-clone determinism before push/install/publication.


## R38 release evidence delta - 2026-10-02T23:15:56.337123+00:00

# R38 release closeout - v1.6.0

Record UTC: 2026-10-02T23:15:56.337123+00:00

## Result and authority

**RELEASED / ACCEPTED.** The eight-page workspace, 48-theme catalog including 20 new Studio geometries, real UI action paths, local analytics, read-only inventory, alerts and presentation profiles are delivered. Release `v1.6.0` ID `402214671` is immutable, stable/latest and has 7/7 matching uploaded digests. Authoritative product source is `1652989b80c5c6d301c6f05818c48c5207fd9b7a`. Post-release documentation commits do not move this tag or change its installed/released bits.

Canonical root: `C:\Users\Aa.Emad\source\repos\TaskbarMonitorEnhanced`.
Installed root: `C:\Users\Aa.Emad\AppData\Local\TaskbarMonitorEnhanced`.
Prior accepted immutable baseline: v1.5.0 at `d952a87fab02fe74046b8d19ae14a2801d6da644`. The corrected worktree source `182c4ed...` was consolidated before final source freeze. `8f19bd2...`, empty-source `f170a8a...`, synthetic workspace evidence and pre-integration installers remain historical **SUPERSEDED — DO NOT RUN** as current release authority. No historical files were globally rewritten or deleted.

## Roadmap and progress

Discovery, definition, baseline, scoped development, verification, validation/acceptance and delivery/release gates are closed with evidence. All product gates for this finite v1.6.0 scope passed. Final handoff packaging uses `.local/r38/BRAIN_R38.zip`, `.local/r38/RUN_R38.zip` and `.local/r38/RETURN_R38.zip`; existence and integrity are determined by their generated manifest/receipt, not by this path declaration. No universal-product-superiority percentage is claimed.

## Verification and validation

All four build projects: zero warnings/errors. All five outputs match a clean clone and the cryptographically verified exact-source CI statements. Candidate visual/model suite 7/7 and runtime suite 8/8 passed; after installation, the same 7/7 and 8/8 passed again. Forty-eight themes render at normal and compact widths. Twenty Studio renderers remain distinct with identical palette/font/data. Eight workspace pages at normal/minimum size, nine Settings pages, sixteen production UI actions, fifty-eight named controls and zero accessibility-name gaps passed.

Manual remote UI validation opened the installed context menu and Workspace, observed accumulating live Overview data, used the 20-Studio filter, previewed Bauhaus and Art Deco, then closed Workspace without stopping Main or changing the configuration. No unrelated desktop content was published.

Installed Main is SHA256 `05F9E069C4598FDAD327A41BF1CA34A1498D022119DB81E09F4B3B091C9BA377`. Setup/installed Uninstall is `f5130bc2f81383e16912454fcc62e307501885a6256e7241e674a9cf10bac9c5`. All five installed outputs and all four new installed source modules match the accepted build. The 69 configuration properties and exact configuration bytes are preserved. Protected sensors remain Broker1.1.2+r21/Supervisor1.3.0+r33, exact binaries reused, health STABLE with zero active consecutive failures in final installed suite. No restart of Windows was performed.

## Failure prevention and resolution

R38-F01: cold-shutdown traffic history loss was reproduced before the correction. Flush must read existing history before writing; corrupt history fails closed; queue completion plus actual I/O result determines success. Red operation920abe69-1532-43d2-a0e4-36966e90f094 failed the new assertion; green36c6d7b0-83ce-401c-808e-3e6c11c4bc0d passed. Source remains guarded by the new regressions.

R38-F02: the validation network could not reach Azure CI-artifact/attestation storage or automatic trust-root initialization. Blind transport retries stopped. The GitHub API supplied the actual signed inline bundles. GitHub CLI verified binaries, runtime config and SPDX predicates using the official Sigstore root pinned at commit644d7f24720ff4cddbc49908ead3c6459e637616, targethash6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66, exact source and workflow. All 5 signed subjects match local files. No TLS/signature check was disabled, no DNS policy was changed, and no successful CI ZIP download is claimed. Verified SBOM predicate was exported with normalized formatting. Operation6361584c-986f-4e88-8b1f-3497f663b4c9 succeeded.

R38-F03: the first installer-runner readiness check reparsed an already-UTC PowerShell DateTime through an implicit string, producing a 3.5-hour false age. It stopped before installation. The corrected runner preserves DateTimeKind or uses ISO roundtrip parsing; typed/string regression passed. Prior backup/evidence was retained. The actual installation occurred once, operation5c3387a9-2d4c-433c-9db0-5fee3e03d443, and completed all installed suites. Never rerun the mutating installer runners.

R38-F04: the new draft existed but GitHub's tag-addressed release read returned404. Reconciliation read the release collection and exact ID402214671, verified the already-uploaded seven assets and published that same draft. No duplicate release or reupload was created. Future draft verification should use the actual draft ID; a failed receipt is not a failed write.

## Evidence and remaining scope

Exact release CI37074301100 and main CI37075175655 passed. Local evidence root `.local/r38` contains BUILD_MANIFEST, DETERMINISM, CI_ACCEPTANCE, candidate/installed suites, configuration/install acceptance, signed-bundle verification, TAG_AUTHORITY, PUBLIC_VERIFICATION, manual UI and preserved pre-states. Public summary is `docs/acceptance/v1.6.0/PUBLIC_RELEASE_ACCEPTANCE.json`.

No critical product gate is open for v1.6.0. Public-trust Authenticode requires an external provider and is explicitly unsigned pending that provider. Physical dual-monitor attachment is not proven on the one-monitor host. Kernel handle/DLL inspection, arbitrary executable plugin ecosystems, exhaustive specialist sensors and overclock/fan controls are outside this accepted scope.

Exact user action: right-click the monitor, open **Theme Studio - 48 designs...**, choose **20 Studio themes**, preview a design and press **Apply selected theme**. No repair/install command is needed. Engineering continuation begins by reading the newest verified Brain, checking the canonical root/HEAD/tag and public acceptance, then creating a new branch/revision; never mutate the immutable release.


## 2026-10-05 — R39 Wallpaper Studio source-candidate milestone

- Context / previous accepted authority: v1.6.0/R38 remains immutable and installed. Product source authority is `1652989b80c5c6d301c6f05818c48c5207fd9b7a`; installed Main SHA-256 remains `05F9E069C4598FDAD327A41BF1CA34A1498D022119DB81E09F4B3B091C9BA377`.
- Decision / scope: new v1.7.0 work is isolated on branch `feature/v1.7.0-wallpaper-studio`. Source candidate commit is `ed46152eb9d9ff326687ba5038aa0990e03102d0`. R38 release/tag/assets were not mutated.
- Confirmed implementation: Studio catalog is now 21 themes, including an original `Sekiro` shinobi/ink renderer. Each Studio theme has exactly 10 deterministic procedural wallpapers, for 210 total. No copied game artwork, downloaded wallpaper pack, font, executable plugin, or external image dependency was added.
- Method choice: wallpapers are generated from each theme's palette/geometry using System.Drawing/GDI+ rather than bundling 210 static bitmap assets. This keeps package growth and external provenance burden low while still producing real PNG outputs. The proof harness hashes rendered pixel files, so the count/uniqueness claim is reproducible rather than inferred.
- UI delta: Theme Studio reaches 49 total themes / 21 Studio themes; Studio selections expose 10 wallpaper variants, preview, single-PNG export, export-all-10, and desktop apply.
- Safety design: desktop apply first records `WallPaper`, `WallpaperStyle`, and `TileWallpaper` to a JSON pre-state record. If registry/SPI application fails after mutation begins, prior registry values and prior wallpaper are restored/attempted before failure is surfaced. No live desktop apply occurred during this milestone.
- Verification / Confirmed: app build PASS with 0 warnings / 0 errors; main selftest PASS with THEMES=49, STUDIO_THEMES=21, WALLPAPERS=210; workspace selftest PASS with 49/21/210; themeproof PASS for all 49 themes.
- Pixel evidence / Confirmed: first wallpaper proof PASSed 21 themes × 10 variants = 210 PNG with 210 unique SHA-256 pixel files. Manifest SHA-256 `ADD7399D47B5B1C1AD52A973572228D33277F76FAADEC8FD6DB233E4D6C8A972`. After the safety/resource quality patch, a new non-overwriting proof PASSed again at 210/210 unique; manifest SHA-256 `1D36FED74044C202AA209536F5301BD34F2C4860689927CE1BD0113999C114EC`.
- Pixel validation / Confirmed: representative visual inspection covered `Sekiro_01`, `Sekiro_05`, `Sekiro_10`, and `Art_Deco_Gold_04`; outputs were valid, visually distinct abstract wallpapers consistent with theme palettes/geometry.
- Host regression / Confirmed: AnyDesk remains active; GUI keyboard input capability reports available/not busy; installed TBME v1.6 runtime and broker/supervisor processes remain active; installed Main hash is unchanged; no `AppData\Local\TaskbarMonitorEnhanced\Wallpapers` directory exists, confirming the R39 proof path did not perform a live wallpaper mutation.
- Failure R39-F01: initial monolithic text patch stopped at an exact-text guard and had malformed csproj quoting. Root cause: brittle line-ending/PowerShell quoting assumptions. Prevention: stopped replay, inspected current diff, repaired csproj from known baseline, then used guarded file-based patch scripts.
- Failure R39-F02: a nested `pwsh -Command` verification wrapper expanded variables in the outer shell, so candidate tests did not execute. Prevention: no product conclusion was drawn; all subsequent runners are file-based `pwsh.exe -File`.
- Failure R39-F03: a WinExe probe printed PASS but PowerShell `$LASTEXITCODE` was empty, causing a false-negative wrapper. Prevention: subsequent verification uses `System.Diagnostics.Process.ExitCode`; main selftest PASS output was retained and not blindly rerun.
- Failure R39-F04: workspace selftest initially expected PublicVersion 1.6.0 after the intentional 1.7.0 source bump. Root cause: stale test contract. Narrow correction to the version assertion followed by rebuild and fresh workspace/wallpaper regressions PASSed.
- Status: `SOURCE_CANDIDATE_PASS_NOT_RELEASED`. Verification is not promotion: installed/public authority is still v1.6.0/R38.
- Open critical path: v1.7 packaging/installer is still hard-coded to v1.6.0; then exact package/determinism acceptance, one reversible live apply/rollback canary, installed v1.7 regression, and release/CI gates.
- Evidence: `docs/acceptance/v1.7.0/R39_SOURCE_CANDIDATE_ACCEPTANCE.json`; local pixel evidence under `.local/r39/wallpaperproof*`.
- Reuse targets: release notes, future installer acceptance, UI documentation, safety design record, engineering handoff.


## 2026-10-05 — R40 v1.7.0 deterministic package candidate accepted

- Context: R39 source candidate remains commit `ed46152eb9d9ff326687ba5038aa0990e03102d0`; v1.6.0/R38 remains the installed/public accepted authority.
- R40 packaging commit: `2cb0baadb127c4b9e8090670d51905ffd2e29627` on `feature/v1.7.0-wallpaper-studio`.
- Packaging delta / Confirmed: Build and Setup identity advanced to v1.7.0; `WallpaperStudio.cs` is included in source preflight, canonical text payload, embedded Setup resources, and installed Source extraction path; v1.7 installer readme/release notes are canonical payload inputs; setup resource contract is 25.
- Determinism control: `.gitattributes` now pins `src/WallpaperStudio.cs` to LF, matching the deterministic source policy used by other canonical modules.
- Package build / Confirmed: all four projects build with 0 warnings / 0 errors; sensor windowless PE gate PASS; canonical text payload PASS; Setup `/verify` PASS with version 1.7.0 and 25 resources.
- Embedded-resource audit / Confirmed: Setup resource count=25; embedded `Payload.WallpaperStudio.cs` SHA-256 `8465B73125FB48C47BE9B3BAD0451A878F3027632AF18E866AF8333E3E0FB157` exactly equals canonical `build/_package_text/WallpaperStudio.cs`. Candidate Main embedded hash is `4A28D46539E67E4EEA5BD2062AD0839AB99B9FC3BB93C6E0BC2CF91A36FFE41F`.
- Setup candidate: `TaskbarMonitorEnhanced_Setup_1.7.0.exe`, SHA-256 `58E844297A0B33E52F05D5023408DB159275BAECDB5C1627DBAEA990CF1237AF`, 11,487,744 bytes.
- Exact-commit clean-clone determinism / Confirmed: PASS at `2cb0baadb127c4b9e8090670d51905ffd2e29627`; evidence `artifacts/DETERMINISM.json`, SHA-256 `E283B9B397BB7F78894B692FA03243535539A45764A21AEB24A3C9D90E0C77E8`.
- Visual package suite / Confirmed: 8/8 PASS — selftest, feature-contract-selftest, workspace-selftest, workspace-proof, themeproof, compactproof, settingsproof, wallpaperproof. Summary SHA-256 `829C39598740D4EA913BAFC817763AF14C9CFD4074C06AD96790888D18FB9AC6`.
- Workspace proof / Confirmed: 8 pages, 49 themes, 21 Studio themes, 210 wallpapers and production UI actions accepted; manifest SHA-256 `789A096A550A85D8939D5985A398F8CD75719F770BF627570FB27678B77CAC85`.
- Wallpaper package proof / Confirmed: 21×10=210 PNG, 210 unique pixel-file hashes; manifest SHA-256 `7B75AE6ED3D27270217DE1FEA4036C0306332D9A08E7363C4000B7EF0D3EAD87`.
- Safety: no installer installation, no live wallpaper mutation, no reboot and no promotion occurred in R40.
- Failure R40-F01: first packaging patch runner stopped before its first mutation because a literal PowerShell `$source` token was incorrectly escaped in the generated patch script. Root cause was orchestration quoting, not product source. Prevention: the failed runner was not replayed; current diff was verified unchanged and a literal here-string guarded patch was used. A later orchestration parser error also occurred before any tool call/mutation and therefore is not product evidence.
- Status: `PACKAGE_CANDIDATE_ACCEPTED_NOT_INSTALLED_NOT_RELEASED`.
- Open critical path: one reversible live Sekiro wallpaper apply/verify/restore canary -> installed v1.7 acceptance -> exact-head CI/provenance and release publication gates.
- Evidence record: `docs/acceptance/v1.7.0/R40_PACKAGE_CANDIDATE_ACCEPTANCE.json`.
- Reuse targets: release engineering, deterministic build audit, installer validation, future handoff.


## R41 | Adaptive glass taskbar overlay | 2026-10-10T03:02:12.193021+00:00
FA​CT / CONFIRMED local candidate: Win32 per-pixel alpha native child overlay and 49 theme styles, 0-100% background opacity, independent opaque text and taskbar color contrast below/equal 30%. Evidence: .local/r41/visual-r41/SUMMARY.json (9/9), .local/r41/visual-r41/glassproof/GLASS_PROOF.json (196/196), .local/r41/live3-proof.json (5 actual parent opacity modes), artifacts/BUILD_MANIFEST.json and setup_verify.json (26 resources), docs/project-control/R41_GLASS_VERIFICATION.md. Previous v1.6 installed/public immutable and protected sensor source unchanged. Prior failures F1..F5 are diagnostic harness failures; no product rewrite. Condition-specific actual taskbar observed RGB #132A27; contrast 15.13. INFERENCE—not confirmed: flawless contrast against every animated/translucent Windows taskbar. OPEN: exact source commit, determinism, CI, wallpaper canary, installed runtime, publication. Do not conflate verification with public validation.


## R42 — 2026-10-10T09:35:22.430426+00:00 — Wallpaper safety failure prevention
FACT: Host user has an active Slideshow BackgroundType=2 and the cached wallpaper SHA rotates. Old ApplyDesktop did not save slideshow settings. R42 source rejects nonstatic background types before generating/applying, stores SHA-verified static image backup and re-verifies rollback. Regression RED compiler CS0117 then GREEN app/self-test. Real host negative reflection test passed with no personalization mutation. Positive isolated canary and installation still pending. Details R42_WALLPAPER_SAFETY.md. Public v1.6 remains accepted; v1.7 not released.

## R44 — 2026-10-10T11:19:04.102467+00:00 — Independent chart foreground
R41 glass moved text into ink but not charts; background alpha 0 removed the chart. R44 fixes regular/extended/Studio sparkline, bars, LCD/dots with independent foreground + halo and conditional graph toggle. RED missing SeedChartHistoryForProof compiler CS1061 then GREEN main build, 196/196 dark/light chart ON/OFF alpha0/29 pair checks across all 49 themes, and 10/10 visual suites. Emad non-installed top-level click-through overlay used 24 real metrics and displayed 1788 separate chart pixels in an actual saved taskbar screenshot; auto expired clean. No user personalization changed. R42 positive wallpaper canary and installed v1.7 gates remain open, issue #7. See R44_RELEASE_GATES_CHECKLIST.md.

## R45 CI and release safety — 2026-10-10T11:44:56.132075+00:00
CI previously ran only three basic workspace tests. R45 explicitly adds 10 visual/graph/alpha suites and 8 runtime CLI probes, with exact counts and manifests in GitHub artifacts. A new 14-gate release-preflight checker verifies actual source/build/proof hashes and distinguishes source candidate from production Stable. Initial YAML-patch CRLF anchor issue and local absolute-path evidence error were harness failures fixed without product mutation; their evidence is in .local/r45. Positive wallpaper, installed v1.7, trusted Authenticode and main acceptance remain BLOCKED. See R45_RELEASE_GATE_ENFORCEMENT.md.

## R45-F3 - 2026-10-10T11:53:16.898134+00:00
The first full CI 38049549463 failed at health due absent installed protected supervisor (expected from ephemeral Windows CI); full local R45 interactive Start test registered only 10/24 required foreground shell samples but cached HWND and screen pixels were healthy. Neither failure was erased. Enforced distinction: five portable CI runtime checks vs eight actual installed host probes. All live interactive thresholds preserved for Stable. Source/CI exact rerun pending.

## R45-F4 2026-10-10T11:59:58.298333+00:00
GitHub CI 38050088052 ran five portable runtime child processes with 0 exit and PASS output each, but the wrapper failed due nullable LASTEXITCODE check on a managed Diagnostics.Process-based script. Script itself did not leave LASTEXITCODE defined. Removed invalid check; retained strict manifest checks and throws. Requires fresh exact CI before source acceptance. Evidence raw GitHub CI log and .local/r45 local 5/5 JSON.

## R46 - 2026-10-10T13:11:42.798032+00:00 - real composited taskbar glass
Root failure: native layered Shell_TrayWnd child success without any readable screen pixels. COMPOSITED+LAYERED child error 87; without COMPOSITED ULW success but actual zero text/chart differences. Fix taskbar-anchored nonactivating TOPLEVEL PArgb below 100%, 100%/HighContrast existing opaque child, high-contrast adaptive foreground ink. Correct WinForms top-level owner vs WS_CHILD semantics and reset layered style after opaque fallback. Actual production OverlayForm proof-only instance records 2319 visible text, 2055 graph pixels, zero transparent-background change; 0->30->97->100->0 all four transitions passed; compiled candidate exact Main digest embedded. Earlier transient harness failures and screenshots preserved in .local/r46. The installed v1.6+Slideshow unchanged; source CI/provenance and new Brain pending. See R46_NATIVE_COMPOSITOR_VERIFICATION.md.

## R49 2026-10-10T14:07:22.093656+00:00
R47 and R48 actual normal app exe temporary installation-path tests on EMAD-PC proved real popup text visible but chart invisible due initial snapshot not refreshing; R48 6/8 interactive tests PASS with Start FAIL, shell not reached. R47/R48 each independently restored installed v1.6 Main/config hashes and resumed process. R47 caller false rollback flag via nullable LASTEXITCODE corrected by independent receipt. R49 code calls PaintPerPixelLayer directly upon each telemetry commit, avoiding unreliable layered HWND WM_PAINT; 2 actual metric-driven ULW uploads in native OverlayForm proof PASS, native glyph/chart still visible. Exact hosted CI/real installed rerun pending. See R49_LIVE_METRIC_REFRESH_VERIFICATION.md.

## R51 2026-10-10T14:51:24.840478+00:00 : Start menu native window mode vs parent
R50 actual installed-path R49 showed 3174 ink/2898 graph with real GPU/CPU/RAM and native top-level PArgb, but the strict eight-probe runtime stopped at START_PROBE_BASELINE_DIRECT_CHILD_GATE (six first probes PASSED). R50 independent watchdog and mandatory v1.6/config rollback both PASSED. R51 StartProbe discovers actual PID-bound native popup when alpha<100 while preserving direct-child rule at 100/high contrast and untouched Start >=18/24, all-window visibility, DWM uncloaked and pixel/geometry criteria. Exact source CI and live eight-host acceptance still required. See R51_STARTPROBE_REAL_WINDOW_MODE.md.

## R54 2026-10-10T16:44:00.955445+00:00: actual compositor band native visibility
R52 normal installed-path Start failed actual screen 0/24 while shell and native HWND good. R53 real taskbar experiments prove TopMost/ULW alone fail 0/24; temporary 60px above taskbar restores foreground 6/6 on each Left/Right. Original Start closure left native popup invisible until same-HWND WinForms Hide/Show, real 2181 glyph and 1906 graph recovery. R54 source StartGuardTick performs bounded noactivate float + same-HWND return; strict 24-frame source-level native proof PASS with 24/24 shell, 24/24 exact safe lift, 24/24 text+chart ink and exact original taskbar return 2291/1907 real pixels. Initial R54-failed 32px jitter on transient UIAutomation rescan preserved and fixed; R54 500ms watchdog premature rescan fixed. Strict StartProbe updated for actual dynamic native popup safe offset and visible post-Start return without lowering sample thresholds. 12 candidate gates incl new G12; 4 external Stable blockers (G13-G16), exact source hosted CI/installed host test pending. See R54_START_FLOATING_NATIVE_ACCEPTANCE.md.

## R56 2026-10-10T16:57:47.715995+00:00 — first 7/8 real installed-host result and native active ShellBeacon fix
R55 actual Main-only in original path R54 source proved 7/8 genuine interactive probes PASS including Start 24/24 shell, 24/24 safe lifted/real-ink frames, post-Start exact return. Last ShellState test FAIL DIRECT_CHILD_NOT_FOUND because its old hard-coded taskbar WS_CHILD requirement ignored native 0%-alpha top-level popup. Independent original v1.6 exe/config restoration PASS; live Slideshow, sensors and AnyDesk unchanged. R56 fixes ShellState mode-aware exact PID/WS_POPUP/layered/noactivate/shell bounds, real synchronous per-pixel beacon + post-clear verification of >100 magenta/green before, <100 each after, with signal>=300. Source exact head CI, normal host 8/8 and full Setup remain to be independently verified. Do not misreport R55 7/8 as PASS.
