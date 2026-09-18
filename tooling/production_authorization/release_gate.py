from __future__ import annotations
from .errors import ProductionAuthorizationCandidateMismatch,ProductionAuthorizationEnvironmentMismatch,ProductionAuthorizationInvalidated
from .models import ProductionAuthorization,ReleaseCandidate
from .validity import AuthorizationEvent,evaluate_authorization

def verify_release_gate(authorization:ProductionAuthorization,candidate:ReleaseCandidate,invalidation_events:tuple[AuthorizationEvent,...]=())->None:
    validity=evaluate_authorization(authorization,candidate,invalidation_events)
    if validity.valid: return
    if "environment_mismatch" in validity.reasons:
        raise ProductionAuthorizationEnvironmentMismatch("authorization target environment does not match release candidate")
    if any(reason.startswith("authorization_") for reason in validity.reasons):
        raise ProductionAuthorizationInvalidated("production authorization is invalidated/revoked")
    raise ProductionAuthorizationCandidateMismatch("production authorization does not match exact release candidate: "+", ".join(validity.reasons))
