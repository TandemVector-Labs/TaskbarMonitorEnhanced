# Code signing policy

Taskbar Monitor Enhanced is an open-source Windows project distributed under **GNU GPL v3.0**. The authoritative repository is:

https://github.com/GOD13emad/TaskbarMonitorEnhanced

## Owner-authorized unsigned distribution

The owner explicitly accepted official unsigned distribution. The current release channel has no claimed SignPath or other public-trust publisher signature. Check the actual installer signature and versioned hashes on [the official latest Release](https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/latest). `NotSigned` is disclosed rather than treated as a trusted signature. Previous releases through the independently observed **v1.7.9** remain immutable, including their owner-accepted unsigned installers.

Any future trusted signing must use a new independently versioned release. Hash verification and GitHub artifact attestations establish file provenance, not antivirus clearance or publisher Authenticode signing.

## Provider and current status

**Potential provider option: SignPath Foundation. A previous open-source application was not approved; a new application has not been accepted and public-trust signing is unavailable.**

The repository contains technical preparation for a potential future SignPath Foundation application. **A prior submission was declined; provider acceptance and a production public-trust signature do not exist.** Reapplication requires a new provider review and stronger independent public-adoption evidence; repository readiness alone is insufficient. The self-signed development certificate documented under `docs/security/` validates the signing pipeline only and is not public publisher trust.

### SignPath Foundation program attribution (conditional; no endorsement or certificate yet)

The following exact wording is required by the SignPath Foundation code-signing policy for projects that are approved to use its certificate:

> Free code signing provided by SignPath.io, certificate by SignPath Foundation

**Current status: a previous Foundation application was not accepted; no current approved signing account or certificate is evidenced, and no published Taskbar Monitor Enhanced binary is claimed to be signed by SignPath Foundation.** This required attribution is included for application readiness, not as a statement that the service, certificate or production signing is available.

The open-source maintainer, reviewers and signing approver are identified in the **Team roles** section below; project privacy and user-controlled network activity are documented in [PRIVACY.md](PRIVACY.md). See the [SignPath Foundation code of conduct](https://signpath.org/terms.html). Public-trust signing additionally requires identical project/product-version metadata for artifacts submitted together, verified GitHub-hosted source-build origin, and explicit approval for each production signing request. Untrusted self-signed development certificates must never be used as public-publisher proof.

Historical release lines, including v1.6.0 and the public v1.7.9 installer, are treated as unsigned unless their **exact** artifact has an independently verifiable Authenticode signature from a publicly trusted provider. Release evidence records `PublicTrust=UNSIGNED_PENDING_EXTERNAL_PROVIDER`; Windows may show **Unknown publisher**. Repository-side readiness is not provider acceptance or a trusted signature.

## Official release artifacts

Only artifacts attached to the official GitHub Releases page are release binaries/packages:

https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases

v1.4.0, v1.3.1, v1.3.0, v1.2.0 and earlier published releases remain immutable historical authorities. No historical tag or release asset is rewritten merely to add a signature. Any future publicly trusted signing change must use a newly versioned release unless the exact published artifact was already signed before publication.

## Team roles

- Committer / maintainer: `GOD13emad`
- Reviewer: `GOD13emad`
- Release and signing approver: `GOD13emad`

This is currently a single-maintainer project. Source changes from external contributors require maintainer review. Every production signing request requires explicit manual approval; signing is never an automatic consequence of a build.

## Build-origin and signing controls

A production signing request must:

1. originate from this public repository and an identified commit;
2. use the repository build scripts and pinned dependency controls;
3. build the Main, Sensor Broker, Sensor Supervisor, and installer artifacts from source;
4. preserve GPL/upstream attribution and documented third-party notices;
5. pass deterministic build and artifact-equivalence checks applicable to that release;
6. generate or update SHA-256 manifests and SPDX SBOM evidence;
7. pass runtime and installer acceptance before public promotion;
8. receive manual release and signing approval;
9. be Authenticode-signed and RFC3161-timestamped by the approved public signing service;
10. be verified after signing and never modified after the signature is applied.

Third-party and open-source dependencies are documented in `THIRD_PARTY_NOTICES.md`. Project signing credentials must never be used to sign unrelated third-party projects or unpublished proprietary code.

## Privacy and network behavior

The application does not upload monitoring telemetry, configuration data, or personal content. By default it performs an HTTPS update check against the official GitHub Releases API; users can disable automatic update checks in Settings. Installer download occurs only after the user confirms the **Download & Install** prompt. Support ZIP export is local and user initiated; its manifest omits machine name and absolute source paths. See [PRIVACY.md](PRIVACY.md) for exact endpoints and behavior.

## Verification and release integrity

Signed status is only one release gate. Users and maintainers must also verify the release tag and commit, published SHA-256 values, SBOM and provenance evidence, and runtime acceptance for the same release identity.

Until a qualified trusted signing provider actually signs a separately versioned release, public-trust signing remains **UNAVAILABLE / NOT APPROVED** even when repository-side release gates pass.

## Provider eligibility checkpoints (updated 29 October 2026)

The latest independently verified public release is **v1.7.9**, published on **29 October 2026**. The GitHub release asset `TaskbarMonitorEnhanced_Setup_1.7.9.exe` is **8,577,536 bytes**, with a GitHub SHA-256 digest `3ae5e2ac7428c3443ff7768c543117af864e7c73f68d32efad4ab40b30fb5b0e`. The *exact identical SHA-256* was independently measured for the owner's local installer; Windows `Get-AuthenticodeSignature` returned `NotSigned` for those identical installer bytes. The release channel also includes the explicit owner-accepted unsigned-installation record `V1_7_9_OWNER_UNSIGNED_ACCEPTANCE.json`. This verifies the currently distributed official installer is **unsigned**; it does NOT mean signed, trusted, malicious or unsafe. The release manifest, SHA-256 values, SPDX SBOM and source archive support file/source verification; **none of these makes its existing Windows installer Authenticode-signed**. No historical release bytes will be replaced under an existing tag.

- **SignPath Foundation:** an earlier application was declined. The repository already offers an OSI-approved GPL-3.0 license, a versioned public Windows installer, a source archive, an SPDX SBOM, and independent GitHub provenance/testing evidence. It also documents upstream attribution and explicitly excludes the separately licensed protected PawnIO binary from the project OSS installer. This technical preparation does not resolve the Foundation's independent **public reputation/adoption** criterion. No acceptance or issue of a SignPath Foundation signing credential exists; a new provider review would be required.
- **SignPath upstream/fork provenance gate (NOT YET CLEARED):** `COPYRIGHT_AND_ATTRIBUTION.md` and `UPSTREAM_REFERENCE_GPL_NOTICE.md` identify this application as derivative GPL-3.0 work from `leandrosa81/taskbar-monitor`. The canonical `GOD13emad/TaskbarMonitorEnhanced` repository currently has GitHub `fork=false` rather than a visible GitHub fork relationship. SignPath Foundation's [own-binaries/upstream policy](https://signpath.org/terms.html) imposes additional requirements if a project signs its *modified upstream* builds (including visible fork lineage, signed upstream builds, and reviewed corresponding branches). The current derivative has an **independent Git root commit** `4307824c4c1cdb3138b81f0fca6019c00439ed2e` dated 16 August 2026, and the checked-out local repository contains no Git object for upstream's latest tagged commit `4c441ccc0a54a745357988839b7632e7141fe803`; therefore direct fork/branch ancestry cannot be assumed. **Actual Authenticode verification of the three most recent upstream release installers on Windows returned `NotSigned`**: [v0.5.4](https://github.com/leandrosa81/taskbar-monitor/releases/tag/v0.5.4), [v0.5.3](https://github.com/leandrosa81/taskbar-monitor/releases/tag/v0.5.3), and [v0.5.2](https://github.com/leandrosa81/taskbar-monitor/releases/tag/v0.5.2). Each exact EXE matched the corresponding GitHub asset's published SHA-256 before `Get-AuthenticodeSignature` was checked; no EXE was executed and all temporary files were cleaned. This is evidence **against** the normal 'upstream publishes signed builds' criterion for the last three versions, not proof that every historical upstream build lacks a signature. The applicability of any provider-approved exception or alternate original-source signing lane remains **UNVERIFIED**. Do not claim SignPath upstream compliance, alter Git history/fork metadata, or submit these installer bytes for signing until the applicable policy is reviewed and the provider accepts the actual provenance. This is a separate gate from the historical low-adoption rejection.
- **OSSign (Open Source Codesigning Initiative):** an additional potential no-fee sponsorship route for established, reviewable open-source software; **new applications are currently suspended** by OSSign due to backlog. Its published minimum requires six months of genuine activity for account/organization AND project (including limits for forks), demonstrable users/community, and publicly verifiable release automation; politically focused, controversial or primarily offensive-security software can be excluded. The actual developer account was created on **17 November 2021**, but this specific repository was only created on **15 August 2026**. The earliest simple six-month repository milestone is **15 February 2027**, not an approval date; earlier proven project development, if any, would need independent provider judgment. Legal eligibility for a subscriber or maintainer actually resident in Iran, the approved signing scope and the reopening of applications are **UNCONFIRMED**. An OSSign inquiry was acknowledged on 28 October 2026 as ticket **991308**. This is not acceptance of an application under the program, not a reopening of new admissions, and not issuance of any signing credential.
- **Certum Open Source Code Signing (low-cost, distinct product):** this is a 1-year, **individual-only** product for free/noncommercial open-source distribution. Certum's [official required-documents policy](https://support.certum.eu/en/code-signing-required-documents/) requires actual subscriber identity verification, a utility bill issued to the applicant, and a publicly accessible ongoing open-source project whose visible materials substantiate the individual's maintainer relationship. The issued certificate has `Open Source Developer` in the subject Common Name and Organization field; it **must not** be portrayed as an ordinary individual Standard publisher identity. Certum explicitly warns it will **revoke** the certificate if used to sign commercially distributed software. Therefore it cannot be a universal cross-project certificate for paid, proprietary or otherwise ineligible offerings. The [SimplySign cloud listing](https://shop.certum.eu/open-source-code-signing-on-simplysign.html) advertised `from EUR 49` but `out of stock` when last checked; lower `from EUR 25` pricing on other Certum pages may refer to an activation code **requiring an already owned crypto card**, not a usable new cloud certificate. A *separate, nonbinding* Open Source eligibility/availability question was emailed to `infolinia@certum.pl` on 29 October 2026, and a Certum trust-services support representative subsequently confirmed on **29 October 2026** that the specific Iranian-residence eligibility inquiry had been **forwarded to Sales**. This is a human escalation, **not** Sales/Compliance approval. Genuine residence in Iran, sanctions screening, current stock, cloud activation, lawful payment and exact project coverage remain **UNAPPROVED / UNVERIFIED**. No KYC, purchase or signing was started. Do not gather/upload an ID or utility bill until the issuer confirms a secure lawful process.
- **Commercial Standard certificate:** Certum/Asseco sales explicitly replied in writing on **26 October 2026** that it can *conditionally* issue a Standard Code Signing certificate to an individual from Iran **provided the applicant is not on sanctions lists**. This is a meaningful preliminary sales confirmation, **not** completed residence/compliance clearance, KYC or an actual issued credential. A written nonbinding 1-year itemized quotation and questions about actual residence in Iran, SimplySign cloud activation, lawful payment and first-party networking/VPN/remote-admin scope were emailed to Sales in October 2026. No compliant final quotation or explicit approval of real Iranian residency has been verified as of 29 October 2026. Standard is the proper product to investigate for lawful commercial first-party software. The actual complete quote, fulfillment, remote activation and permitted product categories remain unresolved; no order has been authorized.
- **Microsoft Store MSIX:** Microsoft's individual developer onboarding currently waives the registration fee in supported markets, but requires government-ID/selfie verification. Store signing is limited to an accepted app submitted in that distribution model. It does not Authenticode-sign or convert existing standalone EXE installers; legal/account eligibility for a developer genuinely resident in Iran is **not verified**, despite support inquiries sent in October 2026. Do not provide identity documents or select a false country to test an unsupported enrollment flow.
- **Additional commercial CA preflight (29 October 2026):** Preliminary eligibility/total-price/OSS-discount inquiries to SSL.com and Sectigo were sent, expressly disclosing actual Iranian residence and asking about lawfully usable cloud signing. These are **unanswered nonbinding requests**, not accepted orders, credentials, sanctions clearance or vendor approval.

For a future newly versioned, genuinely approved release, stage the exact first-party artifacts and verify Windows Authenticode publisher/chain, timestamp, filenames and post-sign hashes independently. Never sign embedded third-party components as though they were original project binaries. Do not treat GitHub/Sigstore provenance, SHA-256 hashes or development self-signed certificates as publicly trusted Authenticode.

Primary requirements: [OSSign eligibility/status](https://ossign.org/), [SignPath Foundation terms](https://signpath.org/terms.html), [Certum Open Source product](https://shop.certum.eu/open-source-code-signing-on-simplysign.html), [Certum certificate verification](https://support.certum.eu/en/code-signing-required-documents/) and [Microsoft Windows signing options](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options).

## Security reporting

See [SECURITY.md](SECURITY.md) for vulnerability reporting. Suspected signing-key, artifact-origin, or release-integrity incidents must block signing and publication until investigated.
