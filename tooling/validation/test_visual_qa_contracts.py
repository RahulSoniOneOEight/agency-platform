from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tooling.visual_qa.errors import VisualQaSchemaInvalid
from tooling.visual_qa.qa_contracts import (
    AUTHORITY_ORDER,
    build_authority_bundle,
    dedupe_key,
    load_qa_schema,
    normalize_region,
    validate_authority_bundle,
    validate_candidate,
    validate_finding,
    validate_finding_against_schema,
)
from tooling.visual_qa.visual_provider import (
    CommandVisualQaProvider,
    FixtureVisualQaProvider,
    parse_provider_output,
)

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "client-projects" / "schema" / "qa-finding.schema.json"
TEMPLATE_PATH = ROOT / "templates" / "qa-finding.json"


def candidate(**overrides: object) -> dict:
    base = {
        "category": "spacing",
        "severity": "major",
        "summary": "Product-card spacing is inconsistent with the governed token.",
        "surface": "prototype",
        "screen": "commerce.home",
        "state": "default",
        "direction": "b",
        "section": "home.product-grid",
        "screenshot_ref": "sha256:capture-1",
        "rule_source": "design_contract",
        "rule_ref": "spacing.card.gap",
        "confidence": 0.91,
    }
    base.update(overrides)
    return base


class SchemaContractTests(unittest.TestCase):
    def test_schema_and_template_exist(self):
        self.assertTrue(SCHEMA_PATH.exists(), SCHEMA_PATH)
        self.assertTrue(TEMPLATE_PATH.exists(), TEMPLATE_PATH)

    def test_template_validates_against_the_schema(self):
        schema = load_qa_schema()
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        validate_finding_against_schema(template, schema)

    def test_template_is_a_domain_valid_finding(self):
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(template, validate_finding(template))

    def test_template_dedupe_key_is_reproducible(self):
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            dedupe_key(template, client_id=template["client_id"]),
            template["dedupe_key"],
        )

    def test_a_non_reproducible_dedupe_key_is_rejected(self):
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        template["dedupe_key"] = "qa-dedupe:v1|wrong"
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_finding(template)

    def test_promoted_finding_requires_a_feedback_id(self):
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        template["status"] = "promoted"
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_finding(template)

    def test_region_containment_is_enforced_beyond_the_schema(self):
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        template["region"] = {"x": 0.8, "y": 0, "width": 0.5, "height": 0.5}
        validate_finding_against_schema(template)
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_finding(template)

    def test_schema_required_keys_match_the_canonical_key_set(self):
        schema = load_qa_schema()
        self.assertEqual(
            {
                "id",
                "client_id",
                "status",
                "severity",
                "category",
                "surface",
                "screen",
                "story",
                "state",
                "direction",
                "mix_ref",
                "section",
                "region",
                "screenshot_ref",
                "source_commit_sha",
                "rule_source",
                "rule_ref",
                "baseline_ref",
                "summary",
                "evidence",
                "confidence",
                "dedupe_key",
                "feedback_id",
                "no_longer_reproducible",
                "recurrences",
                "history",
            },
            set(schema["required"]),
        )

    def test_schema_forbids_a_blocking_field(self):
        schema = load_qa_schema()
        properties = schema["properties"]
        self.assertNotIn("blocking", properties)
        self.assertNotIn("review_status", properties)
        self.assertNotIn("approval", properties)

    def test_invalid_template_is_rejected(self):
        schema = load_qa_schema()
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        template["severity"] = "critical"
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_finding_against_schema(template, schema)


class CandidateValidationTests(unittest.TestCase):
    def test_a_complete_candidate_is_accepted(self):
        normalized = validate_candidate(candidate())
        self.assertEqual("spacing", normalized["category"])
        self.assertEqual("design_contract", normalized["rule_source"])

    def test_provider_output_without_rule_source_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate({"summary": "overflow", "severity": "major"})

    def test_unknown_severity_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(severity="critical"))

    def test_unknown_rule_source_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(rule_source="model_intuition"))

    def test_missing_summary_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(summary="  "))

    def test_prototype_candidate_requires_a_screen(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(screen=None))

    def test_widgetbook_candidate_requires_a_story(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(
                candidate(surface="widgetbook", screen=None, story=None)
            )

    def test_widgetbook_candidate_accepts_a_story(self):
        normalized = validate_candidate(
            candidate(surface="widgetbook", screen=None, story="AgencyButton.Primary")
        )
        self.assertEqual("AgencyButton.Primary", normalized["story"])

    def test_confidence_outside_unit_range_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(confidence=1.5))
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(confidence=-0.1))

    def test_candidate_requires_a_screenshot_reference(self):
        payload = candidate()
        del payload["screenshot_ref"]
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(payload)

    def test_unknown_candidate_fields_are_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(notes="free-form narration"))

    def test_normalized_candidate_is_consumable_by_the_dart_contract(self):
        normalized = validate_candidate(candidate())
        self.assertEqual(
            {
                "category",
                "severity",
                "summary",
                "surface",
                "screen",
                "story",
                "state",
                "direction",
                "mix_ref",
                "section",
                "region",
                "screenshot_ref",
                "rule_source",
                "rule_ref",
                "baseline_ref",
                "confidence",
                "evidence",
            },
            set(normalized.keys()),
        )

    def test_prototype_candidate_must_not_declare_a_story(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(story="AgencyButton.Primary"))

    def test_widgetbook_candidate_must_not_declare_a_screen(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(
                candidate(
                    surface="widgetbook",
                    screen="commerce.home",
                    story="AgencyButton.Primary",
                )
            )

    def test_candidate_must_not_smuggle_review_authority(self):
        for forbidden in (
            "feedback_id",
            "blocking",
            "review_status",
            "approval",
            "resolved",
            "quality_score",
        ):
            with self.assertRaises(VisualQaSchemaInvalid):
                validate_candidate(candidate(**{forbidden: "x"}))

    def test_a_single_quality_score_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_candidate(candidate(score=0.8))


class RegionTests(unittest.TestCase):
    def test_normalized_region_is_accepted(self):
        region = normalize_region({"x": 0.1, "y": 0.42, "width": 0.8, "height": 0.24})
        self.assertEqual({"x": 0.1, "y": 0.42, "width": 0.8, "height": 0.24}, region)

    def test_out_of_range_region_is_rejected(self):
        for bad in (
            {"x": -0.1, "y": 0, "width": 0.5, "height": 0.5},
            {"x": 0.8, "y": 0, "width": 0.5, "height": 0.5},
            {"x": 0, "y": 0, "width": 0, "height": 0.5},
            {"x": 0, "y": 0, "width": 1.2, "height": 0.5},
        ):
            with self.assertRaises(VisualQaSchemaInvalid):
                normalize_region(bad)

    def test_non_numeric_region_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            normalize_region({"x": "left", "y": 0, "width": 1, "height": 1})


class DedupeTests(unittest.TestCase):
    def test_same_issue_produces_the_same_dedupe_key(self):
        first = candidate(confidence=0.5)
        second = candidate(confidence=0.99)
        self.assertEqual(
            dedupe_key(first, client_id="prototype-demo"),
            dedupe_key(second, client_id="prototype-demo"),
        )

    def test_dedupe_key_matches_the_dart_formula(self):
        self.assertEqual(
            "qa-dedupe:v1|prototype-demo|prototype|commerce.home|"
            "design_contract|spacing.card.gap|spacing|home.product-grid||",
            dedupe_key(candidate(), client_id="prototype-demo"),
        )

    def test_different_rule_category_or_region_changes_the_key(self):
        base = dedupe_key(candidate(), client_id="prototype-demo")
        self.assertNotEqual(
            base,
            dedupe_key(candidate(rule_ref="spacing.section.gap"), client_id="prototype-demo"),
        )
        self.assertNotEqual(
            base, dedupe_key(candidate(category="clipping"), client_id="prototype-demo")
        )
        self.assertNotEqual(
            base,
            dedupe_key(
                candidate(section=None, region={"x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2}),
                client_id="prototype-demo",
            ),
        )

    def test_dedupe_key_excludes_commit_and_severity(self):
        base = dedupe_key(candidate(), client_id="prototype-demo")
        self.assertEqual(
            base, dedupe_key(candidate(severity="blocker"), client_id="prototype-demo")
        )


class AuthorityBundleTests(unittest.TestCase):
    def test_authority_order_is_descending(self):
        self.assertEqual(
            [
                "approved_experience",
                "design_contract",
                "accepted_baseline",
                "linked_reference",
                "visual_heuristic",
            ],
            AUTHORITY_ORDER,
        )

    def test_bundle_layers_are_emitted_in_authority_order(self):
        bundle = build_authority_bundle(
            approved_experience={"ref": "approved-experience.yaml"},
            design_contract={"ref": "design-contract/tokens"},
            accepted_baseline={"ref": "baseline-001"},
            linked_references=[{"ref": "client-reference.png"}],
            visual_heuristics=[{"ref": "heuristics/generic"}],
        )
        self.assertEqual(AUTHORITY_ORDER, [layer["source"] for layer in bundle["layers"]])
        self.assertEqual(
            list(range(len(AUTHORITY_ORDER))),
            [layer["authority_rank"] for layer in bundle["layers"]],
        )

    def test_no_layer_may_claim_to_override_higher_authority(self):
        bundle = build_authority_bundle(approved_experience={"ref": "x"})
        for layer in bundle["layers"]:
            self.assertFalse(layer["overrides_higher_authority"])

    def test_out_of_order_bundle_is_rejected(self):
        bundle = build_authority_bundle(
            approved_experience={"ref": "x"}, design_contract={"ref": "y"}
        )
        bundle["layers"] = list(reversed(bundle["layers"]))
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_authority_bundle(bundle)

    def test_an_ordered_subset_is_accepted(self):
        bundle = build_authority_bundle(
            approved_experience={"ref": "x"}, design_contract={"ref": "y"}
        )
        bundle["layers"] = bundle["layers"][:2]
        validate_authority_bundle(bundle)

    def test_unknown_authority_source_is_rejected(self):
        bundle = build_authority_bundle(approved_experience={"ref": "x"})
        bundle["layers"][0]["source"] = "model_intuition"
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_authority_bundle(bundle)

    def test_bundle_claiming_heuristics_override_is_rejected(self):
        bundle = build_authority_bundle(approved_experience={"ref": "x"})
        bundle["layers"][-1]["overrides_higher_authority"] = True
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_authority_bundle(bundle)


class ProviderTransportTests(unittest.TestCase):
    def test_structured_provider_output_is_parsed(self):
        raw = json.dumps({"findings": [candidate()]})
        findings = parse_provider_output(raw)
        self.assertEqual(1, len(findings))
        self.assertEqual("spacing", findings[0]["category"])

    def test_bare_list_provider_output_is_parsed(self):
        raw = json.dumps([candidate()])
        self.assertEqual(1, len(parse_provider_output(raw)))

    def test_free_form_prose_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            parse_provider_output("The layout looks a bit cramped to me.")

    def test_json_without_findings_is_rejected(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            parse_provider_output(json.dumps({"summary": "looks fine"}))

    def test_malformed_finding_in_output_is_rejected(self):
        raw = json.dumps({"findings": [{"summary": "overflow"}]})
        with self.assertRaises(VisualQaSchemaInvalid):
            parse_provider_output(raw)

    def test_fixture_provider_is_deterministic_and_offline(self):
        provider = FixtureVisualQaProvider([candidate()])
        bundle = build_authority_bundle(design_contract={"ref": "design-contract/tokens"})
        context = {"client_id": "prototype-demo", "screen": "commerce.home"}
        first = provider.review({"capture_id": "sha256:1"}, context, bundle)
        second = provider.review({"capture_id": "sha256:1"}, context, bundle)
        self.assertEqual(first, second)
        self.assertEqual("fixture", provider.name)

    def test_fixture_provider_rejects_invalid_fixture_candidates(self):
        with self.assertRaises(VisualQaSchemaInvalid):
            FixtureVisualQaProvider([{"summary": "overflow"}])

    def test_command_provider_rejects_free_form_output(self):
        provider = CommandVisualQaProvider(
            [sys.executable, "-c", "print('this is prose, not json')"]
        )
        bundle = build_authority_bundle()
        with self.assertRaises(VisualQaSchemaInvalid):
            provider.review({"capture_id": "sha256:1"}, {}, bundle)

    def test_command_provider_parses_structured_output(self):
        script = (
            "import json,sys;"
            "sys.stdin.read();"
            "print(json.dumps({'findings': ["
            "{'category':'spacing','severity':'minor','summary':'gap drift',"
            "'surface':'prototype','screen':'commerce.home','state':'default',"
            "'screenshot_ref':'sha256:capture-1',"
            "'rule_source':'visual_heuristic','rule_ref':'heuristic.spacing'}]}))"
        )
        provider = CommandVisualQaProvider([sys.executable, "-c", script])
        findings = provider.review(
            {"capture_id": "sha256:1"}, {}, build_authority_bundle()
        )
        self.assertEqual(1, len(findings))
        self.assertEqual("spacing", findings[0]["category"])


class FindingShapeContractTests(unittest.TestCase):
    def test_normalized_candidate_maps_onto_the_finding_schema(self):
        schema = load_qa_schema()
        finding = {
            "id": "qa-001",
            "client_id": "prototype-demo",
            "status": "detected",
            "severity": "major",
            "category": "spacing",
            "surface": "prototype",
            "screen": "commerce.home",
            "story": None,
            "state": "default",
            "direction": "b",
            "mix_ref": None,
            "section": "home.product-grid",
            "region": None,
            "screenshot_ref": "sha256:abc",
            "source_commit_sha": "abc123",
            "rule_source": "design_contract",
            "rule_ref": "spacing.card.gap",
            "baseline_ref": None,
            "summary": "gap drift",
            "evidence": [],
            "confidence": 0.9,
            "dedupe_key": dedupe_key(candidate(), client_id="prototype-demo"),
            "feedback_id": None,
            "no_longer_reproducible": False,
            "recurrences": 0,
            "history": [
                {
                    "event": "detected",
                    "actor_id": "visual-qa",
                    "at": "2026-09-17T10:00:00.000Z",
                }
            ],
        }
        validate_finding_against_schema(finding, schema)

    def test_finding_schema_rejects_a_blocking_key(self):
        schema = load_qa_schema()
        template = json.loads(TEMPLATE_PATH.read_text(encoding="utf-8"))
        template["blocking"] = True
        with self.assertRaises(VisualQaSchemaInvalid):
            validate_finding_against_schema(template, schema)

    def test_visual_qa_tooling_never_writes_feedback_records(self):
        for path in sorted((ROOT / "tooling" / "visual_qa").glob("*.py")):
            source = path.read_text(encoding="utf-8")
            for needle in ("FeedbackRecord", "feedback_record", "createFeedback"):
                self.assertNotIn(
                    needle,
                    source,
                    f"{path.name} references {needle}",
                )


if __name__ == "__main__":
    unittest.main()
