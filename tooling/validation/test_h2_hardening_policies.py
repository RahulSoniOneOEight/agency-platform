"""Deterministic H.2 hardening-policy tests (Milestone H.2, Task 4).

These tests are Flutter-free and network-free: they exercise
``validate_hardening_policies`` against the committed reference client and
against controlled temp copies of the real ``production/hardening`` directory.
"""

from __future__ import annotations

import io
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import yaml

from tooling.hardening.policies import (
    HARDENING_RELATIVE,
    POLICY_FILES,
    main,
    validate_hardening_policies,
)

ROOT = Path(__file__).resolve().parents[2]
REFERENCE_CLIENT = ROOT / "client-projects" / "reference-commerce"
HARDENING_DIR = REFERENCE_CLIENT / HARDENING_RELATIVE
PERFORMANCE_BUDGET = HARDENING_DIR / POLICY_FILES["performance"]


class HardeningPolicyValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.client_dir = self.root / "client-projects" / "reference-commerce"
        destination = self.client_dir / HARDENING_RELATIVE
        destination.parent.mkdir(parents=True)
        shutil.copytree(HARDENING_DIR, destination)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _policy_path(self, filename: str) -> Path:
        return self.client_dir / HARDENING_RELATIVE / filename

    def _mutate(self, filename: str, mutate) -> None:
        path = self._policy_path(filename)
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        mutate(data)
        path.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")

    def _assert_stable(self, errors: list[str]) -> None:
        self.assertTrue(errors, errors)
        self.assertEqual(errors, sorted(errors))
        self.assertEqual(errors, sorted(set(errors)))

    def test_valid_copy_passes(self):
        self.assertEqual([], validate_hardening_policies(self.root, self.client_dir))

    def test_missing_policy_file_is_rejected(self):
        self._policy_path(POLICY_FILES["recovery"]).unlink()
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(any("missing policy file" in error for error in errors), errors)

    def test_missing_critical_journey_is_rejected(self):
        self._mutate(
            POLICY_FILES["hardening"],
            lambda policy: policy.__setitem__(
                "critical_journeys",
                [j for j in policy["critical_journeys"] if j != "catalog"],
            ),
        )
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(any("critical_journeys" in error for error in errors), errors)

    def test_non_positive_threshold_is_rejected(self):
        self._mutate(
            POLICY_FILES["performance"],
            lambda policy: policy.__setitem__("critical_api_p95_ms_max", 0),
        )
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(
            any(
                "critical_api_p95_ms_max" in error and "positive" in error
                for error in errors
            ),
            errors,
        )

    def test_unknown_release_outcome_is_rejected(self):
        self._mutate(
            POLICY_FILES["hardening"],
            lambda policy: policy.__setitem__(
                "release_outcomes", ["healthy", "degraded", "failed", "unknown"]
            ),
        )
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(any("release_outcomes" in error for error in errors), errors)

    def test_missing_recovery_mode_is_rejected(self):
        self._mutate(
            POLICY_FILES["recovery"],
            lambda policy: policy.__setitem__(
                "modes",
                [m for m in policy["modes"] if m != "forward-recovery-migration"],
            ),
        )
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(
            any("missing required mode" in error for error in errors), errors
        )

    def test_automated_production_authorization_is_rejected(self):
        self._mutate(
            POLICY_FILES["hardening"],
            lambda policy: policy["production_authorization"].__setitem__(
                "automated", True
            ),
        )
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(
            any("must not be automated" in error for error in errors), errors
        )

    def test_automated_security_authorization_is_rejected(self):
        self._mutate(
            POLICY_FILES["security"],
            lambda policy: policy.__setitem__(
                "automated_production_authorization", True
            ),
        )
        errors = validate_hardening_policies(self.root, self.client_dir)
        self._assert_stable(errors)
        self.assertTrue(
            any("must not be automated" in error for error in errors), errors
        )

    def test_errors_are_deterministic(self):
        self._policy_path(POLICY_FILES["performance"]).unlink()
        first = validate_hardening_policies(self.root, self.client_dir)
        second = validate_hardening_policies(self.root, self.client_dir)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(set(first)))

    def test_main_exit_codes_and_output(self):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(0, main([str(self.client_dir)]))
        self.assertEqual("", buffer.getvalue())

        self._policy_path(POLICY_FILES["recovery"]).unlink()
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(1, main([str(self.client_dir)]))
        self.assertIn("missing policy file", buffer.getvalue())


class ReferenceHardeningPolicyTests(unittest.TestCase):
    def test_reference_performance_budget_is_explicit(self):
        policy = yaml.safe_load(PERFORMANCE_BUDGET.read_text(encoding="utf-8"))
        self.assertEqual(4_500_000, policy["main_js_raw_bytes_max"])
        self.assertEqual(18_000_000, policy["web_build_total_bytes_max"])
        self.assertEqual(1_200, policy["critical_api_p95_ms_max"])
        self.assertEqual(20, policy["baseline_regression_percent_max"])

    def test_reference_policies_exist_and_validate_clean(self):
        for filename in POLICY_FILES.values():
            self.assertTrue((HARDENING_DIR / filename).is_file(), filename)
        self.assertEqual(
            [], validate_hardening_policies(ROOT, REFERENCE_CLIENT)
        )


if __name__ == "__main__":
    unittest.main()
