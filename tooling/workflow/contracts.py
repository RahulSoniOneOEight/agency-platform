"""Machine-readable stage-contract metadata.

``workflows/*.md`` remain the executable instruction authority. The YAML
contracts under ``workflows/contracts/`` declare only deterministic metadata
(ids, paths, and names that already exist in the repository); they never carry
business prose. This module loads those contracts and proves parity with the
numbered Markdown workflows.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from tooling.workflow.state import STAGES


WORKFLOW_DIR_NAME = "workflows"
CONTRACTS_DIR_NAME = "contracts"

CONTRACT_VERSION = 1

REQUIRED_SECTIONS = ("PURPOSE", "READ", "PROCESS", "WRITE", "VALIDATE", "DO NOT", "NEXT")

CONTRACT_KEYS = (
    "stage",
    "version",
    "requires",
    "produces",
    "validators",
    "checkpoints",
    "next",
)
REQUIRES_KEYS = ("stages", "artifacts")

_NUMBERED_WORKFLOW = re.compile(r"(\d{2})-([a-z0-9-]+)\.md")
_SECTION_HEADING = re.compile(r"^##\s+(.+?)\s*$")


class StageContractError(ValueError):
    """Raised when a stage contract file is missing or invalid."""


@dataclass(frozen=True)
class StageContract:
    stage: str
    version: int
    requires_stages: tuple[str, ...]
    requires_artifacts: tuple[str, ...]
    produces: tuple[str, ...]
    validators: tuple[str, ...]
    checkpoints: tuple[str, ...]
    next_stages: tuple[str, ...]


def workflow_filename(stage: str) -> str:
    """Return the numbered Markdown workflow filename for a canonical stage."""
    return f"{STAGES.index(stage) + 1:02d}-{stage}.md"


def contract_filename(stage: str) -> str:
    """Return the numbered YAML contract filename for a canonical stage."""
    return f"{STAGES.index(stage) + 1:02d}-{stage}.yaml"


def contract_path(root: Path, stage: str) -> Path:
    return Path(root) / WORKFLOW_DIR_NAME / CONTRACTS_DIR_NAME / contract_filename(stage)


def _string_list(value: Any, label: str) -> tuple[str, ...]:
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item for item in value
    ):
        raise StageContractError(f"{label} must be a list of non-empty strings")
    return tuple(value)


def _stage_list(value: Any, label: str) -> tuple[str, ...]:
    stages = _string_list(value, label)
    for stage in stages:
        if stage not in STAGES:
            raise StageContractError(f"{label} references unknown stage {stage!r}")
    return stages


def _parse_contract(stage: str, data: Any, source: Path) -> StageContract:
    if not isinstance(data, dict):
        raise StageContractError(f"{source}: contract must be a mapping")

    unknown = sorted(set(data) - set(CONTRACT_KEYS))
    if unknown:
        raise StageContractError(f"{source}: unknown key {unknown[0]!r}")
    missing = [key for key in CONTRACT_KEYS if key not in data]
    if missing:
        raise StageContractError(f"{source}: missing key {missing[0]!r}")

    declared_stage = data["stage"]
    if not isinstance(declared_stage, str) or not declared_stage:
        raise StageContractError(f"{source}: invalid stage {declared_stage!r}")
    if declared_stage != stage:
        raise StageContractError(
            f"{source}: stage {declared_stage!r} does not match expected stage {stage!r}"
        )

    version = data["version"]
    if isinstance(version, bool) or not isinstance(version, int):
        raise StageContractError(f"{source}: version must be an integer")

    requires = data["requires"]
    if not isinstance(requires, dict):
        raise StageContractError(f"{source}: requires must be a mapping")
    unknown_requires = sorted(set(requires) - set(REQUIRES_KEYS))
    if unknown_requires:
        raise StageContractError(f"{source}: unknown requires key {unknown_requires[0]!r}")
    missing_requires = [key for key in REQUIRES_KEYS if key not in requires]
    if missing_requires:
        raise StageContractError(f"{source}: missing requires key {missing_requires[0]!r}")

    return StageContract(
        stage=declared_stage,
        version=version,
        requires_stages=_stage_list(requires["stages"], f"{source}: requires.stages"),
        requires_artifacts=_string_list(
            requires["artifacts"], f"{source}: requires.artifacts"
        ),
        produces=_string_list(data["produces"], f"{source}: produces"),
        validators=_string_list(data["validators"], f"{source}: validators"),
        checkpoints=_string_list(data["checkpoints"], f"{source}: checkpoints"),
        next_stages=_stage_list(data["next"], f"{source}: next"),
    )


def load_stage_contract(root: Path, stage: str) -> StageContract:
    if stage not in STAGES:
        raise StageContractError(f"unknown stage {stage!r}")
    path = contract_path(root, stage)
    if not path.exists():
        raise StageContractError(f"{path}: missing stage contract for {stage}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise StageContractError(f"{path}: invalid yaml: {exc}") from exc
    return _parse_contract(stage, data, path)


def load_all_stage_contracts(root: Path) -> list[StageContract]:
    return [load_stage_contract(root, stage) for stage in STAGES]


def _markdown_sections(text: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    current: str | None = None
    buffer: list[str] = []
    for line in text.splitlines():
        match = _SECTION_HEADING.match(line)
        if match:
            if current is not None:
                sections[current] = "\n".join(buffer)
            current = match.group(1)
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        sections[current] = "\n".join(buffer)
    return sections


def _parse_next_stages(text: str) -> tuple[str, ...]:
    body = _markdown_sections(text).get("NEXT", "")
    match = _NUMBERED_WORKFLOW.search(body)
    if not match:
        return ()
    return (match.group(2),)


def validate_stage_contracts(root: Path) -> list[str]:
    """Return deterministic, sorted, path-prefixed parity errors (empty == valid)."""
    root = Path(root)
    workflow_dir = root / WORKFLOW_DIR_NAME
    contracts_dir = workflow_dir / CONTRACTS_DIR_NAME
    errors: list[str] = []
    markdown_next: dict[str, tuple[str, ...]] = {}

    for stage in STAGES:
        md_path = workflow_dir / workflow_filename(stage)
        if not md_path.exists():
            errors.append(f"{md_path}: missing workflow file for {stage}")
            continue
        text = md_path.read_text(encoding="utf-8")
        for section in REQUIRED_SECTIONS:
            if f"## {section}" not in text:
                errors.append(f"{md_path}: missing section {section}")
        markdown_next[stage] = _parse_next_stages(text)

    expected = {contract_filename(stage) for stage in STAGES}
    if contracts_dir.is_dir():
        present = {path.name for path in contracts_dir.glob("*.yaml")}
        for extra in sorted(present - expected):
            errors.append(f"{contracts_dir / extra}: unexpected stage contract file")

    for stage in STAGES:
        path = contracts_dir / contract_filename(stage)
        if not path.exists():
            errors.append(f"{path}: missing stage contract for {stage}")
            continue
        try:
            contract = load_stage_contract(root, stage)
        except StageContractError as exc:
            errors.append(str(exc))
            continue
        if stage in markdown_next and contract.next_stages != markdown_next[stage]:
            errors.append(
                f"{path}: next {list(contract.next_stages)!r} conflicts with "
                f"Markdown NEXT {list(markdown_next[stage])!r}"
            )

    return sorted(errors)
