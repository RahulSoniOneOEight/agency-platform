from __future__ import annotations

from datetime import datetime

from .eligibility import evaluate_eligibility
from .errors import (
    ProductionAuthorizationActorNotAllowed,
    ProductionAuthorizationNotEligible,
)
from .models import ProductionAuthorization, ReleaseActor, ReleaseCandidate
from .repository import ProductionAuthorizationRepository


class ProductionAuthorizationCoordinator:
    """Thin human-authorized orchestration boundary for Milestone G."""

    def __init__(self, repository: ProductionAuthorizationRepository):
        self._repository = repository

    def authorize(
        self,
        candidate: ReleaseCandidate,
        *,
        actor: ReleaseActor,
        authorized_at: datetime,
    ) -> ProductionAuthorization:
        if not actor.is_human_release_owner:
            raise ProductionAuthorizationActorNotAllowed(
                "only a human release_owner may create ProductionAuthorization"
            )
        eligibility = evaluate_eligibility(candidate)
        if not eligibility.eligible:
            codes = ", ".join(reason.code for reason in eligibility.reasons)
            raise ProductionAuthorizationNotEligible(
                f"candidate is not eligible for production authorization: {codes}"
            )

        existing = self._repository.list(candidate.client_id, candidate.environment)
        next_version = 1 if not existing else existing[-1].authorization_version + 1
        supersedes = None if not existing else existing[-1].authorization_version
        authorization = ProductionAuthorization(
            authorization_id=(
                f"pa-{candidate.client_id}-{candidate.environment}-{next_version:04d}"
            ),
            authorization_version=next_version,
            client_id=candidate.client_id,
            environment=candidate.environment,
            approval_version=candidate.approval_version,
            approval_review_state_hash=candidate.approval_review_state_hash,
            approval_source_commit_sha=candidate.approval_source_commit_sha,
            source_commit_sha=candidate.source_commit_sha,
            build_artifact_id=candidate.build_artifact_id,
            build_hash=candidate.build_hash,
            qa_evidence_ids=tuple(item.evidence_id for item in candidate.qa_evidence),
            validation_evidence_ids=tuple(
                item.evidence_id for item in candidate.validation_evidence
            ),
            security_evidence_ids=tuple(
                item.evidence_id for item in candidate.security_evidence
            ),
            rollback_plan_ref=candidate.rollback_plan_ref,
            migration_plan_ref=candidate.migration_plan_ref,
            release_notes_ref=candidate.release_notes_ref,
            acknowledged_non_blocking_item_ids=(
                candidate.acknowledged_non_blocking_item_ids
            ),
            supporting_evidence_refs=candidate.supporting_evidence_refs,
            authorized_by=actor,
            authorized_at=authorized_at,
            supersedes=supersedes,
        )
        self._repository.create(authorization)
        return authorization
