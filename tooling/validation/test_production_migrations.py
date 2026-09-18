from __future__ import annotations

import io
import re
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from tooling.production.validate_migrations import (
    MIGRATION_CLASS_SEMANTICS,
    SUPPORTED_CLASSES,
    main,
    validate_migrations,
)

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "supabase" / "migrations"
SEED = ROOT / "supabase" / "seed" / "reference_commerce_seed.sql"

REQUIRED_TABLES = (
    "profiles",
    "business_accounts",
    "account_memberships",
    "credit_snapshots",
    "categories",
    "products",
    "variants",
    "inventory",
    "carts",
    "cart_items",
    "orders",
    "order_items",
    "rfqs",
    "quotations",
)

RLS_TABLES = (
    "profiles",
    "business_accounts",
    "account_memberships",
    "credit_snapshots",
    "carts",
    "cart_items",
    "orders",
    "order_items",
    "rfqs",
    "quotations",
)

ADDITIVE = "-- migration-class: additive\n"


def _write_migration(directory: Path, name: str, body: str) -> Path:
    path = directory / name
    path.write_text(body, encoding="utf-8")
    return path


class MigrationValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.migrations = self.root / "supabase" / "migrations"
        self.migrations.mkdir(parents=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_ordered_versioned_migrations_are_valid(self):
        _write_migration(self.migrations, "202609180001_alpha.sql", ADDITIVE + "select 1;\n")
        _write_migration(
            self.migrations,
            "202609180002_beta.sql",
            "-- migration-class: transformative\nselect 2;\n",
        )
        self.assertEqual([], validate_migrations(self.root))

    def test_duplicate_version_is_rejected(self):
        _write_migration(self.migrations, "202609180001_alpha.sql", ADDITIVE)
        _write_migration(self.migrations, "202609180001_beta.sql", ADDITIVE)
        errors = validate_migrations(self.root)
        self.assertTrue(
            any("duplicate migration version 202609180001" in error for error in errors),
            errors,
        )

    def test_missing_class_header_is_rejected(self):
        _write_migration(self.migrations, "202609180001_alpha.sql", "select 1;\n")
        errors = validate_migrations(self.root)
        self.assertTrue(any("missing migration-class header" in error for error in errors), errors)

    def test_unsupported_class_is_rejected(self):
        _write_migration(
            self.migrations,
            "202609180001_alpha.sql",
            "-- migration-class: sideways\nselect 1;\n",
        )
        errors = validate_migrations(self.root)
        self.assertTrue(any("unsupported migration-class" in error for error in errors), errors)

    def test_multiple_class_headers_are_rejected(self):
        _write_migration(
            self.migrations,
            "202609180001_alpha.sql",
            "-- migration-class: additive\n-- migration-class: destructive\nselect 1;\n",
        )
        errors = validate_migrations(self.root)
        self.assertTrue(
            any("multiple migration-class headers" in error for error in errors), errors
        )

    def test_migration_class_semantics_are_documented(self):
        self.assertEqual(SUPPORTED_CLASSES, frozenset(MIGRATION_CLASS_SEMANTICS))
        for migration_class, description in MIGRATION_CLASS_SEMANTICS.items():
            self.assertTrue(description.strip(), migration_class)

    def test_invalid_migration_filename_is_rejected(self):
        _write_migration(self.migrations, "not_a_migration.sql", ADDITIVE)
        errors = validate_migrations(self.root)
        self.assertTrue(any("invalid migration filename" in error for error in errors), errors)

    def test_missing_migrations_directory_is_rejected(self):
        empty_root = self.root / "empty"
        empty_root.mkdir()
        errors = validate_migrations(empty_root)
        self.assertTrue(any("missing migrations directory" in error for error in errors), errors)

    def test_errors_are_stable_and_sorted(self):
        _write_migration(self.migrations, "202609180001_alpha.sql", "select 1;\n")
        _write_migration(self.migrations, "202609180001_beta.sql", ADDITIVE)
        _write_migration(
            self.migrations,
            "202609180002_gamma.sql",
            "-- migration-class: sideways\n",
        )
        _write_migration(self.migrations, "bad-name.sql", ADDITIVE)
        first = validate_migrations(self.root)
        second = validate_migrations(self.root)
        self.assertEqual(first, second)
        self.assertEqual(first, sorted(first))
        self.assertTrue(first)

    def test_validator_does_not_execute_sql(self):
        _write_migration(
            self.migrations,
            "202609180001_broken.sql",
            ADDITIVE + "this is not valid sql; drop table definitely_missing;\n",
        )
        self.assertEqual([], validate_migrations(self.root))

    def test_main_exit_codes_and_output(self):
        _write_migration(self.migrations, "202609180001_alpha.sql", ADDITIVE)
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(0, main([str(self.root)]))
        self.assertEqual("", buffer.getvalue())

        _write_migration(self.migrations, "202609180002_beta.sql", "select 1;\n")
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(1, main([str(self.root)]))
        self.assertIn("missing migration-class header", buffer.getvalue())


class ReferenceMigrationTests(unittest.TestCase):
    def test_repository_migrations_are_valid(self):
        self.assertEqual([], validate_migrations(ROOT))

    def test_foundation_migration_declares_required_tables(self):
        foundation = MIGRATIONS / "202609180001_reference_commerce_foundation.sql"
        self.assertTrue(foundation.exists(), foundation)
        sql = foundation.read_text(encoding="utf-8").lower()
        for table in REQUIRED_TABLES:
            pattern = rf"create table(?: if not exists)? public\.{table}\b"
            self.assertRegex(sql, pattern, f"missing table {table}")

    def test_rls_migration_enables_rls_on_owned_tables(self):
        rls = MIGRATIONS / "202609180002_reference_commerce_rls.sql"
        self.assertTrue(rls.exists(), rls)
        sql = rls.read_text(encoding="utf-8").lower()
        for table in RLS_TABLES:
            pattern = rf"alter table public\.{table} enable row level security"
            self.assertRegex(sql, pattern, f"missing rls on {table}")
        self.assertIn("account_memberships", sql)

    def test_seed_is_synthetic_and_deterministic(self):
        self.assertTrue(SEED.exists(), SEED)
        text = SEED.read_text(encoding="utf-8")
        lowered = text.lower()
        self.assertNotIn("password", lowered)
        self.assertNotIn("@gmail.com", lowered)
        self.assertNotIn("service_role", lowered)
        for email in re.findall(r"[a-z0-9._%+-]+@[a-z0-9.-]+", lowered):
            self.assertTrue(
                email.endswith(".invalid") or email.endswith(".example"),
                f"non-synthetic email: {email}",
            )


class RlsPolicySemanticTests(unittest.TestCase):
    """Static assertions on the RLS SQL text (the validator never executes SQL)."""

    @classmethod
    def setUpClass(cls) -> None:
        rls = MIGRATIONS / "202609180002_reference_commerce_rls.sql"
        cls.sql = rls.read_text(encoding="utf-8")

    def _policy(self, name: str) -> str:
        match = re.search(rf"create policy {name}\b.*?;", self.sql, re.DOTALL)
        self.assertIsNotNone(match, f"missing policy {name}")
        return match.group(0)

    def test_identity_bearing_account_writes_require_identity_and_membership(self):
        for name in (
            "carts_insert_owner_or_buyer",
            "carts_update_owner_or_buyer",
            "orders_insert_owner_or_buyer",
            "orders_update_manager",
            "rfqs_insert_buyer_or_manager",
            "rfqs_update_manager",
            "account_memberships_manage_manager",
        ):
            block = self._policy(name)
            self.assertIn("identity_id = auth.uid()", block, name)
            self.assertIn("has_account_role", block, name)

    def test_update_policies_bind_identity_on_using_and_with_check(self):
        for name in (
            "carts_update_owner_or_buyer",
            "orders_update_manager",
            "rfqs_update_manager",
            "account_memberships_manage_manager",
        ):
            block = self._policy(name)
            self.assertGreaterEqual(block.count("identity_id = auth.uid()"), 2, name)

    def test_consumer_writes_are_limited_to_personal_rows(self):
        for name in (
            "carts_insert_owner_or_buyer",
            "carts_update_owner_or_buyer",
            "carts_delete_owner_or_manager",
            "orders_insert_owner_or_buyer",
        ):
            block = self._policy(name)
            self.assertIn("account_id is null", block, name)
            self.assertIn("identity_id = auth.uid()", block, name)

    def test_no_unconstrained_identity_or_membership_disjunction(self):
        self.assertNotRegex(
            self.sql,
            r"identity_id = auth\.uid\(\)\s+or\s+public\.has_account_role",
        )

    def test_child_writes_are_scoped_by_personal_parent_or_membership(self):
        for name in (
            "cart_items_insert_owner_or_buyer",
            "cart_items_update_owner_or_buyer",
            "cart_items_delete_owner_or_manager",
            "order_items_insert_owner_or_buyer",
        ):
            block = self._policy(name)
            self.assertIn("account_id is null", block, name)
            self.assertIn("has_account_role", block, name)

    def test_quotations_remain_manager_scoped_by_account_membership(self):
        for name in (
            "quotations_insert_manager",
            "quotations_update_manager",
            "quotations_delete_manager",
        ):
            block = self._policy(name)
            self.assertIn("has_account_role(rfq.account_id, array['b2b_manager'])", block, name)


if __name__ == "__main__":
    unittest.main()
