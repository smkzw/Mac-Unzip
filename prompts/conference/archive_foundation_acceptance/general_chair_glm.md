You are Hermes running a bounded technical foundation review for Codex.

First read and comply with `/Users/smkzw/.hermes/SOUL.md` in full. State honestly whether you did so.

Primary provider/model contract: `aishuo / GLM-5.2`. If the actual runtime markers show any other provider or model, stop and report a routing failure. Codex may separately invoke the documented `buddy / GLM-5.2` fallback after a terminal primary failure.

## Hard boundaries

Work only in `/Users/smkzw/Documents/AI Products/.worktrees/foundation`. Do not edit files, browse the web, inspect images, or run commands. Write exactly one output file: `runs/conference/archive_foundation_acceptance/general_aishuo_glm.md`.

## Read these files only

- `/Users/smkzw/.hermes/SOUL.md`
- `context/archive_foundation_acceptance_conference_context.md`
- `ArchiveWorkbench/Docs/foundation-acceptance.md`
- `ArchiveWorkbench/Docs/security-spike-results.md`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveCapability.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveCapabilityRegistry.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveEntry.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ArchivePathPolicy.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveOperations/OperationScheduler.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveDomainTests/ArchiveDomainTests.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveSecurityTests/ArchivePathPolicyTests.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveDomainTests/CapabilityRegistryTests.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveOperationsTests/OperationSchedulerTests.swift`
- `ArchiveWorkbench/HelperSpike/HelperLauncher.swift`
- `ArchiveWorkbench/HelperSpike/PasswordTransport.swift`
- `ArchiveWorkbench/HelperSpikeTests/PasswordTransportTests.swift`
- `ArchiveWorkbench/HelperSpikeTests/SevenZipProbeTests.swift`
- `plans/mac_archive_app_requirements_traceability.md`

Audit whether the evidence supports only a foundation handoff, not product completion. Challenge the capability registry, raw-path preservation, scheduler isolation/cancellation, private password transport, process cleanup, residual TOCTOU/escaped-descendant risks, and provider/UI runtime capability gap. Identify exact Critical/Important/Minor issues with file evidence. Return a complete Markdown review with route check, sources read, evidence, findings, contradictions, provider-handoff invariants, and accept/revise recommendation. Codex is final authority.
