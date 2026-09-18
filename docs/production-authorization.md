# Production Authorization

Milestone G adds a release-authority boundary after client approval and QA.

`ApprovalSnapshot + QA/review blockers clear + validators/security/release evidence + exact source/build identity → ProductionEligibility → explicit human release_owner → immutable ProductionAuthorization → H release gate`.

`ApprovalSnapshot` remains client approval. `ProductionEligibility` is deterministic readiness only. `ProductionAuthorization` is human release permission for one exact client/environment/SHA/build. Milestone H may consume a valid authorization; G never deploys.

OpenCode, agents, CI and QA providers may gather and validate evidence but cannot create a real-client authorization. A changed SHA or build requires reevaluation/new authorization even when client reapproval is unnecessary.

The `reference-commerce/release/` tree is a deterministic synthetic proof fixture. Its committed authorization represents an explicit synthetic human release owner solely for regression testing. The F machine report is supporting evidence, never approval authority.
