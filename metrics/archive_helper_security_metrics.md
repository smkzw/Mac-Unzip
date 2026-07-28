# Metrics: archive_helper_security

Date: 2026-07-12

| Field | Value |
|---|---|
| Task type | `code_scoped_patch_plan` |
| Risk | `high` |
| Selected provider | `reasonix-cli` |
| Selected model | `deepseek-v4-pro` |
| Selected effort | `high` |
| Duration | 4m 07s observed stdout interval |
| API calls | 5 recorded completion/usage entries |
| Artifact size | 28,547 bytes |
| Result | Advisory incorporated after Codex verification; delegation read-boundary failed |

## Verification Burden

High. Codex had to audit the actual read/write transcript, reject the delegation as a compliance pass, independently inspect the implementation, run the pinned provider, and require focused, stress, full-scheme, package, cleanup, signing, and source-scan evidence.

## Routing Decision

Initial route reason: high-risk password/process-lifecycle planning required an adversarial DeepSeek Pro review. The route produced useful security hypotheses, but the unapproved ArchiveSecurity reads demonstrate that future bounded reviews need a stricter copied-source packet or stronger tool enforcement. No provider substitution occurred.
