"""Authority-boundary guards for the workflow runtime.

Milestone E hardens the workflow runtime without absorbing any Milestone C or D
domain authority. The workflow layer may reference domain artifacts by path,
id, or hash, but it must never import, mutate, or re-model review, refinement,
approval, or automated-QA state (RE10, spec §13).
"""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_DIR = ROOT / "tooling" / "workflow"

# Symbols that belong to the C.3-C.7 / D.1-D.4 authorities.
FORBIDDEN_SYMBOLS = (
    "ReviewState",
    "ReviewController",
    "ReviewCoordinator",
    "FeedbackRecord",
    "RefinementBatch",
    "ApprovalSnapshot",
    "QAFinding",
    "QaCoordinator",
    "ProductionAuthorization",
)

# Machinery that would make this a generic workflow/BPM engine (RE11).
FORBIDDEN_MACHINERY = (
    "import asyncio",
    "import threading",
    "import multiprocessing",
    "celery",
    "redis",
    "kafka",
    "rabbitmq",
    "socket",
    "grpc",
)


class WorkflowAuthorityBoundaryTests(unittest.TestCase):
    def _sources(self) -> list[Path]:
        files = sorted(WORKFLOW_DIR.glob("*.py"))
        self.assertTrue(files, "expected workflow runtime sources")
        return files

    def test_workflow_runtime_never_references_c_or_d_authorities(self):
        offenders: list[str] = []
        for path in self._sources():
            source = path.read_text(encoding="utf-8")
            for symbol in FORBIDDEN_SYMBOLS:
                if symbol in source:
                    offenders.append(f"{path.name}: {symbol}")
        self.assertEqual([], offenders)

    def test_workflow_runtime_introduces_no_bpm_machinery(self):
        offenders: list[str] = []
        for path in self._sources():
            source = path.read_text(encoding="utf-8")
            for needle in FORBIDDEN_MACHINERY:
                if needle in source:
                    offenders.append(f"{path.name}: {needle}")
        self.assertEqual([], offenders)

    def test_only_the_runner_and_initializer_write_workflow_state(self):
        # `state.py` defines the writers; every other module must not call them.
        writers: list[str] = []
        for path in self._sources():
            if path.name == "state.py":
                continue
            source = path.read_text(encoding="utf-8")
            if "save_state_atomic(" in source or "save_state(" in source:
                writers.append(path.name)
        self.assertEqual(["initialize_client.py", "runner.py"], sorted(writers))

    def test_workflow_graph_is_the_fixed_nine_stage_sequence(self):
        from tooling.workflow.state import STAGES

        self.assertEqual(
            [
                "client-intake",
                "resolve-intelligence",
                "resource-research",
                "generate-directions",
                "build-prototype",
                "visual-qa",
                "client-review",
                "productionize",
                "release",
            ],
            STAGES,
        )
        from tooling.workflow.contracts import load_all_stage_contracts

        contracts = load_all_stage_contracts(ROOT)
        self.assertEqual(tuple(STAGES), tuple(c.stage for c in contracts))
        for index, contract in enumerate(contracts):
            expected = () if index == len(STAGES) - 1 else (STAGES[index + 1],)
            self.assertEqual(expected, contract.next_stages)


if __name__ == "__main__":
    unittest.main()
