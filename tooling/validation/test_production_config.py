from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from tooling.production.validate_config import (
    ALLOWED_KEYS,
    FORBIDDEN_KEY_FRAGMENTS,
    REQUIRED_ENVIRONMENTS,
    main,
    validate_production_config,
)

ROOT = Path(__file__).resolve().parents[2]
REFERENCE_CLIENT = ROOT / "client-projects" / "reference-commerce"

BASE_CONFIG: dict[str, object] = {
    "environment": "dev",
    "api_base_url": "https://api.dev.agency-platform.example",
    "supabase_url": "",
    "supabase_anon_key": "",
    "analytics_enabled": False,
    "feature_flags": {"b2b_rfq": True},
    "integration_modes": {"payment": "fake"},
    "app_version": "0.1.0",
}


def _valid_config(environment: str) -> dict[str, object]:
    config = json.loads(json.dumps(BASE_CONFIG))
    config["environment"] = environment
    return config


class ProductionConfigValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.client_dir = self.root / "client-projects" / "reference-commerce"
        self.config_dir = self.client_dir / "production" / "config"
        self.config_dir.mkdir(parents=True)
        for environment in REQUIRED_ENVIRONMENTS:
            self._write(environment, _valid_config(environment))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write(self, environment: str, payload: object) -> Path:
        path = self.config_dir / f"{environment}.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_valid_configs_pass(self):
        self.assertEqual([], validate_production_config(self.root, self.client_dir))

    def test_missing_environment_is_rejected(self):
        (self.config_dir / "production.json").unlink()
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("missing production environment config" in error for error in errors),
            errors,
        )

    def test_wrong_environment_name_is_rejected(self):
        self._write("dev", _valid_config("staging"))
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("environment must be 'dev'" in error for error in errors),
            errors,
        )

    def test_unsupported_top_level_key_is_rejected(self):
        config = _valid_config("dev")
        config["db_host"] = "localhost"
        self._write("dev", config)
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("unsupported configuration key: db_host" in error for error in errors),
            errors,
        )

    def test_privileged_keys_are_rejected_recursively(self):
        for fragment in FORBIDDEN_KEY_FRAGMENTS:
            with self.subTest(fragment=fragment):
                config = _valid_config("dev")
                config["feature_flags"] = {f"flag_{fragment}": True}
                self._write("dev", config)
                errors = validate_production_config(self.root, self.client_dir)
                self.assertTrue(
                    any(
                        "privileged configuration key" in error and fragment in error
                        for error in errors
                    ),
                    errors,
                )

    def test_hyphenated_privileged_key_is_rejected(self):
        config = _valid_config("dev")
        config["feature_flags"] = {"service-role-enabled": True}
        self._write("dev", config)
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("privileged configuration key" in error for error in errors),
            errors,
        )

    def test_invalid_json_is_rejected(self):
        (self.config_dir / "dev.json").write_text("{ not json", encoding="utf-8")
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(any("invalid JSON" in error for error in errors), errors)

    def test_non_object_config_is_rejected(self):
        self._write("dev", ["not", "an", "object"])
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("must be a JSON object" in error for error in errors),
            errors,
        )

    def test_missing_api_base_url_is_rejected(self):
        config = _valid_config("dev")
        del config["api_base_url"]
        self._write("dev", config)
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("api_base_url must be a non-empty string" in error for error in errors),
            errors,
        )

    def test_wrong_value_type_is_rejected(self):
        config = _valid_config("dev")
        config["analytics_enabled"] = "yes"
        self._write("dev", config)
        errors = validate_production_config(self.root, self.client_dir)
        self.assertTrue(
            any("analytics_enabled must be a boolean" in error for error in errors),
            errors,
        )

    def test_missing_config_directory_is_rejected(self):
        empty_root = self.root / "empty"
        empty_root.mkdir()
        errors = validate_production_config(empty_root, empty_root / "missing")
        self.assertTrue(
            any("missing production config directory" in error for error in errors),
            errors,
        )

    def test_errors_are_stable_and_sorted(self):
        (self.config_dir / "production.json").unlink()
        self._write("dev", _valid_config("staging"))
        first = validate_production_config(self.root, self.client_dir)
        second = validate_production_config(self.root, self.client_dir)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first))
        self.assertTrue(first)

    def test_main_exit_codes_and_output(self):
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(0, main([str(self.client_dir)]))
        self.assertEqual("", buffer.getvalue())

        (self.config_dir / "production.json").unlink()
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(1, main([str(self.client_dir)]))
        self.assertIn("missing production environment config", buffer.getvalue())


class ReferenceProductionConfigTests(unittest.TestCase):
    def test_repository_reference_configs_are_valid(self):
        self.assertEqual([], validate_production_config(ROOT, REFERENCE_CLIENT))

    def test_reference_configs_declare_all_environments(self):
        for environment in REQUIRED_ENVIRONMENTS:
            path = (
                REFERENCE_CLIENT
                / "production"
                / "config"
                / f"{environment}.json"
            )
            self.assertTrue(path.is_file(), path)
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(environment, payload["environment"])

    def test_reference_configs_use_only_client_safe_keys(self):
        for environment in REQUIRED_ENVIRONMENTS:
            path = (
                REFERENCE_CLIENT
                / "production"
                / "config"
                / f"{environment}.json"
            )
            payload = json.loads(path.read_text(encoding="utf-8"))
            self.assertTrue(set(payload).issubset(ALLOWED_KEYS), set(payload))
            self.assertNotIn("service_role", json.dumps(payload).lower())
            self.assertNotIn("webhook_secret", json.dumps(payload).lower())
            self.assertNotIn("payment_secret", json.dumps(payload).lower())
            self.assertNotIn("whatsapp_token", json.dumps(payload).lower())


if __name__ == "__main__":
    unittest.main()
