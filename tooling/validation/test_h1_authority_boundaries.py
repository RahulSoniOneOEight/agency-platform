"""H.1 authority-boundary tests (Milestone H.1, Task 9).

H.1 is production implementation only. It must not create or substitute for an
existing authority:

- it never imports the G coordinator to create a ``ProductionAuthorization``;
- it never writes a production deployment artifact;
- it duplicates no approval/review/QA authority under ``production/``;
- Flutter configuration carries no privileged secret key;
- Supabase imports appear only in the Supabase adapter and the app composition
  boundary.
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from tooling.production.report import build_h1_report
from tooling.production.validate_config import (
    ALLOWED_KEYS,
    FORBIDDEN_KEY_FRAGMENTS,
    REQUIRED_ENVIRONMENTS,
)


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "client-projects" / "reference-commerce"
PRODUCTION_DIR = CLIENT / "production"

H1_TOOLING_DIR = ROOT / "tooling" / "production"
H1_PACKAGE_DIRS = (
    ROOT / "packages" / "agency_production_core",
    ROOT / "packages" / "agency_supabase_adapter",
    ROOT / "packages" / "agency_integration_adapters",
    ROOT / "apps" / "production_app",
)

# Deployment commands H.1 must never invoke.
DEPLOYMENT_TOKENS = (
    "kubectl",
    "docker push",
    "gcloud ",
    "flutter build",
    "deploy_production",
    "execute_release",
)

# Write verbs that, applied to the release/authorization area, would mean H.1
# produced a production deployment artifact.
WRITE_VERBS = ("write_text", "write_bytes", "shutil.copy", "os.replace", "os.rename")
AUTHORIZATION_AREA_MARKERS = ("production-authorizations", "authorization-v", "/release/")

AUTHORITY_NAME_PATTERN = re.compile(
    r"^(approval|review|qa|feedback|refinement|authorization|production-authorization)"
    r"|^qafinding|^workflow-state\.yaml$",
    re.IGNORECASE,
)

_IMPORT_PATTERN = re.compile(
    r"^\s*(?:from|import)\s+tooling\.production_authorization", re.MULTILINE
)

SUPABASE_IMPORT_PATTERN = re.compile(r"import\s+'package:supabase[a-z_]*/")

ALLOWED_SUPABASE_IMPORT_FILES = frozenset(
    {
        "apps/production_app/lib/app/production_composition_root.dart",
    }
)


def _relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _python_files(directory: Path):
    return sorted(directory.rglob("*.py"))


def _dart_lib_files(directory: Path):
    lib = directory / "lib"
    if not lib.is_dir():
        return []
    return sorted(lib.rglob("*.dart"))


class H1AuthorityBoundaryTests(unittest.TestCase):
    def test_h1_tooling_does_not_import_the_g_authorization_coordinator(self):
        for path in _python_files(H1_TOOLING_DIR):
            source = path.read_text(encoding="utf-8")
            relative = _relative(path)
            self.assertIsNone(_IMPORT_PATTERN.search(source), relative)
            self.assertNotIn("ProductionAuthorizationCoordinator", source, relative)
            self.assertNotIn("ProductionAuthorizationRepository", source, relative)

    def test_h1_dart_does_not_reference_production_authorization(self):
        for directory in H1_PACKAGE_DIRS:
            for path in _dart_lib_files(directory):
                source = path.read_text(encoding="utf-8")
                self.assertNotIn("ProductionAuthorization", source, _relative(path))
                self.assertNotIn("production_authorization", source, _relative(path))

    def test_h1_code_writes_no_production_deployment_artifact(self):
        for path in _python_files(H1_TOOLING_DIR):
            lowered = path.read_text(encoding="utf-8").lower()
            for token in DEPLOYMENT_TOKENS:
                self.assertNotIn(token, lowered, f"{_relative(path)}: {token}")
            for line in lowered.splitlines():
                if not any(marker in line for marker in AUTHORIZATION_AREA_MARKERS):
                    continue
                for verb in WRITE_VERBS:
                    self.assertNotIn(
                        verb, line, f"{_relative(path)}: writes {line.strip()}"
                    )
        for directory in H1_PACKAGE_DIRS:
            for path in _dart_lib_files(directory):
                lowered = path.read_text(encoding="utf-8").lower()
                for token in DEPLOYMENT_TOKENS:
                    self.assertNotIn(token, lowered, f"{_relative(path)}: {token}")

    def test_h1_report_declares_no_authorization_or_deployment(self):
        checks = build_h1_report(ROOT, CLIENT)["authority_checks"]
        self.assertIs(False, checks["h1_creates_production_authorization"])
        self.assertIs(False, checks["h1_performs_production_deployment"])

    def test_no_authority_is_duplicated_under_production(self):
        self.assertTrue(PRODUCTION_DIR.is_dir(), PRODUCTION_DIR)
        offenders = []
        for path in sorted(PRODUCTION_DIR.rglob("*")):
            if AUTHORITY_NAME_PATTERN.search(path.name):
                offenders.append(_relative(path))
        self.assertEqual([], offenders, offenders)

    def test_production_contains_only_implementation_artifacts(self):
        entries = {path.name for path in PRODUCTION_DIR.iterdir()}
        self.assertEqual({"config", "fixtures", "evidence"}, entries)

    def test_no_production_authorization_file_exists_under_production(self):
        self.assertFalse(
            list(PRODUCTION_DIR.rglob("*authorization*")),
            "H.1 must never write an authorization artifact under production/",
        )

    def test_flutter_configs_contain_no_forbidden_secret_key(self):
        config_paths = sorted(
            (PRODUCTION_DIR / "config").glob("*.json")
        ) + sorted(
            (ROOT / "apps" / "production_app" / "assets" / "config").glob("*.json")
        )
        self.assertTrue(config_paths, "no production config files found")
        for path in config_paths:
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertTrue(
                set(payload).issubset(ALLOWED_KEYS),
                f"{_relative(path)}: {sorted(set(payload) - ALLOWED_KEYS)}",
            )
            serialized = json.dumps(payload).lower()
            for fragment in FORBIDDEN_KEY_FRAGMENTS:
                self.assertNotIn(fragment, serialized, f"{_relative(path)}: {fragment}")

    def test_reference_configs_cover_every_environment(self):
        for environment in REQUIRED_ENVIRONMENTS:
            path = PRODUCTION_DIR / "config" / f"{environment}.json"
            self.assertTrue(path.is_file(), path)
            self.assertEqual(
                environment,
                json.loads(path.read_text(encoding="utf-8"))["environment"],
            )

    def test_supabase_imports_appear_only_at_the_adapter_or_composition_boundary(self):
        offenders = []
        for directory in H1_PACKAGE_DIRS:
            for path in _dart_lib_files(directory):
                source = path.read_text(encoding="utf-8")
                if not SUPABASE_IMPORT_PATTERN.search(source):
                    continue
                relative = _relative(path)
                if relative in ALLOWED_SUPABASE_IMPORT_FILES:
                    continue
                if relative.startswith("packages/agency_supabase_adapter/lib/"):
                    continue
                offenders.append(relative)
        self.assertEqual([], offenders, offenders)


if __name__ == "__main__":
    unittest.main()
