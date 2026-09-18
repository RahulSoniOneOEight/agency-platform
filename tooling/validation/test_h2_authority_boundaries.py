"""H.2 authority-boundary guards (Milestone H.2, Task 12).

Deterministic and offline. These tests prove the H.2 hardening and release code
cannot absorb an existing authority:

- no ``tooling/release`` or ``tooling/hardening`` code path imports the G
  authorization coordinator/repository or creates/mutates an authorization;
- ``agency_operations_core`` carries no provider SDK or adapter import (the
  provider-neutral core contract boundary);
- client files carry no privileged secret value/config;
- workflow state is mutated only through ``tooling.workflow.runner`` (and the
  one-time initializer);
- stage 08 performs no deployment/authorization and stage 09 consumes the G
  authorization by reference only.
"""

from __future__ import annotations

import ast
import json
import re
import unittest
from collections.abc import Mapping
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
H2_TOOLING_DIRS = (
    ROOT / "tooling" / "release",
    ROOT / "tooling" / "hardening",
)
OPERATIONS_CORE_LIB = ROOT / "packages" / "agency_operations_core" / "lib"

FORBIDDEN_IMPORT_MODULES = (
    "tooling.production_authorization.coordinator",
    "tooling.production_authorization.repository",
)
FORBIDDEN_IMPORT_NAMES = (
    "ProductionAuthorizationCoordinator",
    "FileProductionAuthorizationRepository",
    "ProductionAuthorizationRepository",
)
FORBIDDEN_CALL_NAMES = ("ProductionAuthorization",)
FORBIDDEN_DEFINITION_NAMES = ("create", "authorize")
FORBIDDEN_SOURCE_MARKERS = (
    "ProductionAuthorizationCoordinator",
    "FileProductionAuthorizationRepository",
    "ProductionAuthorizationRepository",
    ".create(",
    ".authorize(",
)

PROVIDER_SDK_IMPORT_PATTERNS = tuple(
    re.compile(pattern)
    for pattern in (
        r"package:sentry",
        r"package:firebase",
        r"package:google_analytics",
        r"package:ga4",
        r"package:cloudflare",
        r"package:supabase",
        r"package:postgres",
        r"package:postgrest",
        r"package:agency_sentry_adapter",
        r"package:agency_ga4_adapter",
        r"package:agency_cloudflare_adapter",
        r"package:agency_supabase_adapter",
    )
)

PRIVILEGED_SECRET_MARKERS = (
    "service_role",
    "service-role",
    "SUPABASE_SERVICE_ROLE_KEY",
    "-----BEGIN",
    "ghp_",
    "sk_live_",
    "sk_test_",
    "AKIA",
    "Bearer ey",
)

ALLOWED_STATE_WRITERS = {
    ROOT / "tooling" / "workflow" / "state.py",
    ROOT / "tooling" / "workflow" / "initialize_client.py",
    ROOT / "tooling" / "workflow" / "runner.py",
}

AUTHORIZATION_BODY_MARKERS = ("authorized_by", "authorized_at", "build", "status", "supersedes")


def _iter_json_keys(value: object):
    """Yield every mapping key in *value*, recursing into nested containers.

    A top-level-only scan would let a nested authorization body (e.g.
    ``{"authorization": {"status": "active"}}``) evade the pointer guard.
    """
    if isinstance(value, Mapping):
        for key, item in value.items():
            yield key
            yield from _iter_json_keys(item)
    elif isinstance(value, list):
        for item in value:
            yield from _iter_json_keys(item)


def _authorization_body_markers_in(value: object) -> list[str]:
    return sorted(
        {key for key in _iter_json_keys(value) if key in AUTHORIZATION_BODY_MARKERS}
    )


def _python_files(directory: Path) -> list[Path]:
    return sorted(directory.rglob("*.py"))


def _relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


class H2AuthorizationCreationBoundaryTests(unittest.TestCase):
    def _modules(self) -> list[Path]:
        modules = [path for directory in H2_TOOLING_DIRS for path in _python_files(directory)]
        self.assertTrue(modules, "authority-boundary scan is vacuous")
        return modules

    def test_h2_tooling_never_imports_or_constructs_authorization_creation(self):
        for path in self._modules():
            source = path.read_text(encoding="utf-8")
            relative = _relative(path)
            tree = ast.parse(source)
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom):
                    self.assertNotIn(node.module or "", FORBIDDEN_IMPORT_MODULES, relative)
                    for alias in node.names:
                        self.assertNotIn(alias.name, FORBIDDEN_IMPORT_NAMES, relative)
                elif isinstance(node, ast.Import):
                    for alias in node.names:
                        self.assertNotIn(alias.name, FORBIDDEN_IMPORT_NAMES, relative)
                elif isinstance(node, ast.Call):
                    func = node.func
                    name = (
                        func.id
                        if isinstance(func, ast.Name)
                        else func.attr
                        if isinstance(func, ast.Attribute)
                        else ""
                    )
                    self.assertNotIn(name, FORBIDDEN_CALL_NAMES, relative)
            for marker in FORBIDDEN_SOURCE_MARKERS:
                self.assertNotIn(marker, source, f"{relative}: {marker}")

    def test_h2_tooling_defines_no_authorize_or_create_function(self):
        for path in self._modules():
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    self.assertNotIn(
                        node.name,
                        FORBIDDEN_DEFINITION_NAMES,
                        f"{_relative(path)}:{node.name}",
                    )


class OperationsCoreProviderNeutralityTests(unittest.TestCase):
    def test_operations_core_imports_no_provider_sdk_or_adapter(self):
        files = sorted(OPERATIONS_CORE_LIB.rglob("*.dart"))
        self.assertTrue(files, "expected agency_operations_core sources")
        offenders: list[str] = []
        for path in files:
            for number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if not line.strip().startswith("import"):
                    continue
                for pattern in PROVIDER_SDK_IMPORT_PATTERNS:
                    if pattern.search(line):
                        offenders.append(f"{_relative(path)}:{number}: {line.strip()}")
        self.assertEqual([], offenders, offenders)


class ClientSecretBoundaryTests(unittest.TestCase):
    def test_client_files_contain_no_privileged_secret_value(self):
        offenders: list[str] = []
        for path in sorted(CLIENT.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix.lower() not in {".json", ".yaml", ".yml", ".md", ".txt", ".dart"}:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for marker in PRIVILEGED_SECRET_MARKERS:
                if marker in text:
                    offenders.append(f"{_relative(path)}: {marker}")
        self.assertEqual([], offenders, offenders)


class WorkflowStateAuthorityTests(unittest.TestCase):
    def test_no_tooling_module_outside_the_workflow_runtime_writes_state(self):
        offenders: list[str] = []
        for path in sorted((ROOT / "tooling").rglob("*.py")):
            if "validation" in path.parts or "workflow" in path.parts:
                continue
            source = path.read_text(encoding="utf-8")
            if "save_state_atomic(" in source or "save_state(" in source:
                offenders.append(_relative(path))
        self.assertEqual([], offenders, offenders)

    def test_only_the_runner_initializer_and_state_define_state_writers(self):
        writers: list[Path] = []
        for path in sorted((ROOT / "tooling" / "workflow").glob("*.py")):
            source = path.read_text(encoding="utf-8")
            if "save_state_atomic(" in source or "save_state(" in source:
                writers.append(path)
        self.assertEqual(
            sorted(ALLOWED_STATE_WRITERS),
            sorted(writers),
            [str(path) for path in writers],
        )


class ReleaseAuthorityConsumptionTests(unittest.TestCase):
    def test_stage08_performs_no_deployment_or_authorization(self):
        from tooling.workflow.contracts import load_stage_contract

        contract = load_stage_contract(ROOT, "productionize")
        self.assertEqual(("production-capable",), contract.checkpoints)
        self.assertNotIn("production-authorization", contract.validators)
        text = (ROOT / "workflows" / "08-productionize.md").read_text(encoding="utf-8")
        self.assertIn("Do not deploy production", text)
        self.assertIn("ProductionAuthorization", text)

    def test_stage09_consumes_authorization_by_reference_only(self):
        ref_path = (
            CLIENT / "production" / "release" / "production-authorization-ref.json"
        )
        self.assertTrue(ref_path.is_file(), ref_path)
        ref = json.loads(ref_path.read_text(encoding="utf-8"))
        self.assertEqual(
            [],
            _authorization_body_markers_in(ref),
            "stage 09 must consume authorization by ref, not carry a body field "
            "at any nesting level",
        )
        self.assertIn("authorization_path", ref)
        body_path = ROOT / ref["authorization_path"]
        self.assertFalse(body_path.is_relative_to(CLIENT / "production"))
        self.assertTrue(body_path.is_file(), body_path)
        # Non-tautological: compare the ref to the body actually loaded from the
        # path the ref resolves to, not to the ref itself.
        body = json.loads(body_path.read_text(encoding="utf-8"))
        self.assertEqual(ref["authorization_id"], body.get("authorization_id"))
        self.assertEqual(
            ref["authorization_version"], body.get("authorization_version")
        )
        self.assertEqual(ref["authorization_path"], _relative(body_path))


if __name__ == "__main__":
    unittest.main()
