"""Typed, machine-readable errors for the visual-QA subsystem.

Every error carries a stable ``code`` so callers (CLI, CI, tooling, the Dart
bridge) can branch deterministically instead of parsing prose. Invalid
operations are transactional: a raised error never leaves a successful capture,
a persisted finding, or a rewritten baseline behind.
"""

from __future__ import annotations


class VisualQaError(Exception):
    """Base class for every visual-QA failure."""

    code = "visual_qa_error"

    def __init__(self, message: str) -> None:
        super().__init__(message)
        self.message = message

    def to_json(self) -> dict:
        return {"code": self.code, "message": self.message}


class InvalidCaptureJob(VisualQaError, ValueError):
    """A manifest or capture job that is structurally or semantically invalid."""

    code = "invalid_capture_job"


class CaptureFailed(VisualQaError):
    """A capture backend could not produce a usable screenshot."""

    code = "capture_failed"


class CaptureNotDeterministic(VisualQaError):
    """A capture was produced but could not be shown to be deterministic."""

    code = "capture_not_deterministic"


class InvalidScreenshotMetadata(VisualQaError):
    """Screenshot artifact metadata is missing, malformed, or contradictory."""

    code = "invalid_screenshot_metadata"


class GoldenBaselineMissing(VisualQaError):
    """A required golden baseline does not exist."""

    code = "golden_baseline_missing"


class GoldenMismatch(VisualQaError):
    """A capture differs from its governed baseline."""

    code = "golden_mismatch"


class UnauthorizedBaselineUpdate(VisualQaError):
    """A baseline create/update was attempted without reviewer authority."""

    code = "unauthorized_baseline_update"


class InvalidBaselineIndex(VisualQaError):
    """A governed baseline index is malformed or ambiguous."""

    code = "invalid_baseline_index"


class InvalidQaFinding(VisualQaError):
    """A QA finding candidate failed schema or domain validation."""

    code = "invalid_qa_finding"


class InvalidQaTransition(VisualQaError):
    """A QA finding lifecycle transition the state machine does not allow."""

    code = "invalid_qa_transition"


class VisualQaProviderFailure(VisualQaError):
    """A visual-AI provider failed to produce a review result."""

    code = "visual_qa_provider_failure"


class VisualQaSchemaInvalid(VisualQaError):
    """Provider output did not match the structured review contract."""

    code = "visual_qa_schema_invalid"


class DuplicateFindingPromotion(VisualQaError):
    """A QA finding was already promoted into human review."""

    code = "duplicate_finding_promotion"


class QaFindingNotPromotable(VisualQaError):
    """A QA finding is not in a state that may be promoted."""

    code = "qa_finding_not_promotable"


class QaEvidenceMissing(VisualQaError):
    """A QA operation requires evidence that was not supplied."""

    code = "qa_evidence_missing"
