"""Provider-neutral Visual QA interface and strict structured-output transport.

A provider's only job is to turn screenshots + context + an authority bundle into
a list of **validated candidates**. Providers never approve experience, change
review status, resolve feedback, create refinement batches, mutate runtime, or
update baselines. Model/provider specifics stay behind this seam; ordinary tests
and CI run against deterministic fixtures with no network and no secrets.
"""

from __future__ import annotations

import json
import subprocess
from typing import Protocol, runtime_checkable

from .errors import VisualQaProviderFailure, VisualQaSchemaInvalid
from .qa_contracts import validate_authority_bundle, validate_candidate


@runtime_checkable
class VisualQaProvider(Protocol):
    """Provider-neutral visual review seam."""

    name: str

    def review(
        self,
        screenshot: dict,
        context: dict,
        authority_bundle: dict,
    ) -> list[dict]:
        """Return schema-valid QA candidates for one screenshot."""
        ...


def parse_provider_output(raw: str | bytes) -> list[dict]:
    """Parse and strictly validate a provider's structured output.

    Free-form prose is rejected: the system of record is structured, schema-valid
    data, never model narration.
    """
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="replace")
    if not isinstance(raw, str) or not raw.strip():
        raise VisualQaSchemaInvalid("visual QA provider returned no output")
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError as error:
        raise VisualQaSchemaInvalid(
            "visual QA provider output is not structured JSON"
        ) from error

    if isinstance(decoded, dict):
        findings = decoded.get("findings")
        if findings is None:
            raise VisualQaSchemaInvalid(
                "visual QA provider output requires a findings list"
            )
    elif isinstance(decoded, list):
        findings = decoded
    else:
        raise VisualQaSchemaInvalid("visual QA provider output must be an object or list")

    if not isinstance(findings, list):
        raise VisualQaSchemaInvalid("visual QA provider findings must be a list")
    return [validate_candidate(item) for item in findings]


class FixtureVisualQaProvider:
    """Deterministic, offline provider used by tests and ordinary CI."""

    name = "fixture"

    def __init__(self, candidates: list[dict] | None = None) -> None:
        # Validate eagerly so a malformed fixture fails fast, not at review time.
        self._candidates = [validate_candidate(item) for item in (candidates or [])]

    def review(
        self,
        screenshot: dict,
        context: dict,
        authority_bundle: dict,
    ) -> list[dict]:
        validate_authority_bundle(authority_bundle)
        return [dict(candidate) for candidate in self._candidates]


class CommandVisualQaProvider:
    """Optional adapter that shells out to an external review command.

    The command receives a JSON request on stdin and must emit structured JSON on
    stdout. This is the only place a live model/provider may be wired in; it is
    never required by ordinary tests or CI, and its output is still validated
    against the same contract as the fixture provider.
    """

    name = "command"

    def __init__(
        self,
        command: list[str],
        *,
        timeout_seconds: float = 120.0,
    ) -> None:
        if not command:
            raise VisualQaProviderFailure("visual QA command must not be empty")
        self._command = list(command)
        self._timeout = timeout_seconds

    def review(
        self,
        screenshot: dict,
        context: dict,
        authority_bundle: dict,
    ) -> list[dict]:
        validate_authority_bundle(authority_bundle)
        request = {
            "version": 1,
            "screenshot": screenshot,
            "context": context,
            "authority_bundle": authority_bundle,
        }
        try:
            completed = subprocess.run(
                self._command,
                input=json.dumps(request),
                capture_output=True,
                text=True,
                timeout=self._timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise VisualQaProviderFailure(
                f"visual QA provider command failed: {error}"
            ) from error
        if completed.returncode != 0 and not completed.stdout.strip():
            raise VisualQaProviderFailure(
                "visual QA provider command failed: "
                + (completed.stderr or "").strip()
            )
        return parse_provider_output(completed.stdout)
