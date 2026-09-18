from __future__ import annotations


class ProductionAuthorizationError(Exception):
    code = "production_authorization_error"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message

    def __str__(self) -> str:
        return f"{type(self).__name__}({self.code}): {self.message}"


class ProductionAuthorizationNotEligible(ProductionAuthorizationError):
    code = "production_authorization_not_eligible"


class ProductionAuthorizationVersionConflict(ProductionAuthorizationError):
    code = "production_authorization_version_conflict"


class ProductionAuthorizationImmutable(ProductionAuthorizationError):
    code = "production_authorization_immutable"


class ProductionAuthorizationActorNotAllowed(ProductionAuthorizationError):
    code = "production_authorization_actor_not_allowed"


class ProductionAuthorizationCandidateMismatch(ProductionAuthorizationError):
    code = "production_authorization_candidate_mismatch"


class ProductionAuthorizationEnvironmentMismatch(ProductionAuthorizationError):
    code = "production_authorization_environment_mismatch"


class ProductionAuthorizationEvidenceMissing(ProductionAuthorizationError):
    code = "production_authorization_evidence_missing"


class ProductionAuthorizationEvidenceStale(ProductionAuthorizationError):
    code = "production_authorization_evidence_stale"


class ProductionAuthorizationInvalidated(ProductionAuthorizationError):
    code = "production_authorization_invalidated"


class InvalidReleaseCandidate(ProductionAuthorizationError):
    code = "invalid_release_candidate"


class InvalidProductionAuthorization(ProductionAuthorizationError):
    code = "invalid_production_authorization"
