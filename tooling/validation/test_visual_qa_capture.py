from __future__ import annotations

import json
import unittest
from pathlib import Path

from tooling.prototype.screenshot_manifest import (
    MANIFEST_VERSION,
    STANDARD_VIEWPORTS,
    InvalidCaptureJob,
    build_capture_jobs,
    build_screenshot_manifest,
    normalize_manifest,
)

SCHEMA_PATH = (
    Path(__file__).resolve().parents[2]
    / "client-projects"
    / "schema"
    / "screenshot-manifest.schema.json"
)

DEMO_MANIFEST_PATH = (
    Path(__file__).resolve().parents[2]
    / "client-projects"
    / "examples"
    / "prototype-demo"
    / "prototype"
    / "qa"
    / "screenshot-manifest.yaml"
)

BASE_URL = "http://localhost:8080"
COMMIT = "abc123"


def v2_manifest(**overrides: object) -> dict:
    job = {
        "surface": "prototype",
        "screen": "commerce.home",
        "state": "default",
        "direction": "b",
        "viewport": {"width": 390, "height": 844},
        "device_scale_factor": 1,
    }
    job.update(overrides.pop("job", {}))  # type: ignore[arg-type]
    manifest = {
        "version": 2,
        "client_id": "prototype-demo",
        "fixture_version": "demo-v1",
        "jobs": [job],
    }
    manifest.update(overrides)
    return manifest


class ManifestV2ContractTests(unittest.TestCase):
    def test_manifest_version_constant_is_two(self):
        self.assertEqual(2, MANIFEST_VERSION)

    def test_standard_viewports_are_unchanged(self):
        sizes = {(v["width"], v["height"]) for v in STANDARD_VIEWPORTS}
        self.assertEqual(
            {(360, 800), (390, 844), (430, 932), (768, 1024), (1440, 900)},
            sizes,
        )
        for viewport in STANDARD_VIEWPORTS:
            self.assertTrue(viewport["name"])

    def test_v2_manifest_expands_only_declared_jobs(self):
        jobs = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        self.assertEqual(1, len(jobs))
        self.assertEqual(COMMIT, jobs[0]["source_commit_sha"])
        self.assertTrue(jobs[0]["capture_id"])

    def test_v2_normalization_keeps_declared_job_count(self):
        manifest = v2_manifest()
        manifest["jobs"] = [
            manifest["jobs"][0],
            {
                "surface": "widgetbook",
                "story": "AgencyButton.Primary",
                "state": "hover",
                "viewport": {"name": "desktop"},
            },
        ]
        jobs = build_capture_jobs(manifest, BASE_URL, COMMIT)
        self.assertEqual(2, len(jobs))

    def test_governed_viewport_preset_resolves_to_dimensions(self):
        manifest = v2_manifest(job={"viewport": {"name": "mobile-medium"}})
        job = build_capture_jobs(manifest, BASE_URL, COMMIT)[0]
        self.assertEqual(390, job["viewport"]["width"])
        self.assertEqual(844, job["viewport"]["height"])
        self.assertEqual("mobile-medium", job["viewport"]["name"])

    def test_preset_name_must_match_explicit_dimensions(self):
        manifest = v2_manifest(
            job={"viewport": {"name": "mobile-medium", "width": 400, "height": 900}}
        )
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_unknown_viewport_preset_is_rejected(self):
        manifest = v2_manifest(job={"viewport": {"name": "watch"}})
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_custom_viewport_dimensions_are_allowed_when_explicit(self):
        manifest = v2_manifest(job={"viewport": {"width": 1024, "height": 768}})
        job = build_capture_jobs(manifest, BASE_URL, COMMIT)[0]
        self.assertEqual(1024, job["viewport"]["width"])
        self.assertEqual(768, job["viewport"]["height"])

    def test_viewport_requires_dimensions(self):
        manifest = v2_manifest(job={"viewport": {"name": "mobile-medium"}})
        manifest["jobs"][0]["viewport"] = {"width": 390}
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_unknown_direction_is_rejected(self):
        manifest = v2_manifest(job={"direction": "z"})
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_prototype_job_requires_direction(self):
        manifest = v2_manifest()
        del manifest["jobs"][0]["direction"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_prototype_job_requires_screen(self):
        manifest = v2_manifest()
        del manifest["jobs"][0]["screen"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_unknown_surface_is_rejected(self):
        manifest = v2_manifest(job={"surface": "print"})
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_widgetbook_job_requires_story_and_forbids_screen(self):
        missing_story = v2_manifest()
        missing_story["jobs"] = [
            {"surface": "widgetbook", "state": "default", "viewport": {"width": 390, "height": 844}}
        ]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(missing_story)

        both = v2_manifest()
        both["jobs"] = [
            {
                "surface": "widgetbook",
                "story": "AgencyButton.Primary",
                "screen": "commerce.home",
                "state": "default",
                "viewport": {"width": 390, "height": 844},
            }
        ]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(both)

    def test_widgetbook_job_accepts_story_identity(self):
        manifest = v2_manifest()
        manifest["jobs"] = [
            {
                "surface": "widgetbook",
                "story": "AgencyButton.Primary",
                "state": "default",
                "viewport": {"width": 390, "height": 844},
            }
        ]
        job = build_capture_jobs(manifest, BASE_URL, COMMIT)[0]
        self.assertEqual("widgetbook", job["surface"])
        self.assertEqual("AgencyButton.Primary", job["story"])
        self.assertIsNone(job["screen"])

    def test_state_is_required(self):
        manifest = v2_manifest()
        del manifest["jobs"][0]["state"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_mix_ref_is_optional_and_carried_through(self):
        manifest = v2_manifest(job={"mix_ref": "review-state-v2"})
        job = build_capture_jobs(manifest, BASE_URL, COMMIT)[0]
        self.assertEqual("review-state-v2", job["mix_ref"])

    def test_fixture_version_is_required(self):
        manifest = v2_manifest()
        del manifest["fixture_version"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_client_id_is_required(self):
        manifest = v2_manifest()
        del manifest["client_id"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_empty_jobs_are_rejected(self):
        manifest = v2_manifest()
        manifest["jobs"] = []
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_unsupported_manifest_version_is_rejected(self):
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest({"version": 9, "client_id": "x", "jobs": []})

    def test_non_mapping_manifest_is_rejected(self):
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(["not", "a", "mapping"])

    def test_device_scale_factor_must_be_positive(self):
        manifest = v2_manifest(job={"device_scale_factor": 0})
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_device_scale_factor_defaults_to_one(self):
        manifest = v2_manifest()
        del manifest["jobs"][0]["device_scale_factor"]
        job = build_capture_jobs(manifest, BASE_URL, COMMIT)[0]
        self.assertEqual(1, job["device_scale_factor"])


class CaptureIdentityTests(unittest.TestCase):
    def test_capture_id_is_stable_for_identical_input(self):
        first = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        second = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        self.assertEqual(first[0]["capture_id"], second[0]["capture_id"])

    def test_capture_id_is_independent_of_job_ordering(self):
        manifest = v2_manifest()
        first_job = dict(manifest["jobs"][0])
        second_job = dict(first_job, screen="commerce.search")
        manifest["jobs"] = [first_job, second_job]
        ordered = build_capture_jobs(manifest, BASE_URL, COMMIT)
        manifest["jobs"] = [second_job, first_job]
        reversed_jobs = build_capture_jobs(manifest, BASE_URL, COMMIT)
        self.assertEqual(
            {job["screen"]: job["capture_id"] for job in ordered},
            {job["screen"]: job["capture_id"] for job in reversed_jobs},
        )

    def test_capture_id_changes_with_source_commit(self):
        first = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        second = build_capture_jobs(v2_manifest(), BASE_URL, "def456")
        self.assertNotEqual(first[0]["capture_id"], second[0]["capture_id"])

    def test_capture_id_changes_with_state(self):
        first = build_capture_jobs(v2_manifest(job={"state": "default"}), BASE_URL, COMMIT)
        second = build_capture_jobs(v2_manifest(job={"state": "loading"}), BASE_URL, COMMIT)
        self.assertNotEqual(first[0]["capture_id"], second[0]["capture_id"])

    def test_capture_id_changes_with_viewport(self):
        first = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        second = build_capture_jobs(
            v2_manifest(job={"viewport": {"name": "desktop"}}), BASE_URL, COMMIT
        )
        self.assertNotEqual(first[0]["capture_id"], second[0]["capture_id"])

    def test_capture_id_is_prefixed_and_hashed(self):
        job = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)[0]
        self.assertTrue(job["capture_id"].startswith("sha256:"))
        self.assertEqual(64, len(job["capture_id"].split(":", 1)[1]))

    def test_capture_id_does_not_depend_on_wall_clock(self):
        first = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        second = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)
        self.assertEqual(first[0], second[0])

    def test_identity_carries_every_reproducibility_field(self):
        job = build_capture_jobs(v2_manifest(job={"mix_ref": "mix-1"}), BASE_URL, COMMIT)[0]
        for field in (
            "client_id",
            "surface",
            "screen",
            "state",
            "direction",
            "mix_ref",
            "viewport",
            "device_scale_factor",
            "fixture_version",
            "source_commit_sha",
            "capture_id",
            "url",
            "filename",
        ):
            self.assertIn(field, job)

    def test_filename_is_deterministic_and_filesystem_safe(self):
        job = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)[0]
        self.assertEqual(job["filename"], build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)[0]["filename"])
        for unsafe in ("/", "\\", ":", "?", "*", '"', "<", ">", "|"):
            self.assertNotIn(unsafe, job["filename"])
        self.assertTrue(job["filename"].endswith(".png"))


class CaptureRouteTests(unittest.TestCase):
    def test_route_is_deterministic_and_targets_the_direction(self):
        job = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)[0]
        self.assertEqual(
            "http://localhost:8080/?client=prototype-demo&direction=b", job["url"]
        )

    def test_route_carries_the_mix_reference(self):
        job = build_capture_jobs(
            v2_manifest(job={"mix_ref": "review-state-v2"}), BASE_URL, COMMIT
        )[0]
        self.assertIn("mix=review-state-v2", job["url"])

    def test_base_url_trailing_slash_is_normalized(self):
        job = build_capture_jobs(v2_manifest(), "http://localhost:8080/", COMMIT)[0]
        self.assertEqual(
            "http://localhost:8080/?client=prototype-demo&direction=b", job["url"]
        )

    def test_widgetbook_route_targets_the_story(self):
        manifest = v2_manifest()
        manifest["jobs"] = [
            {
                "surface": "widgetbook",
                "story": "AgencyButton.Primary",
                "state": "default",
                "viewport": {"width": 390, "height": 844},
            }
        ]
        job = build_capture_jobs(manifest, BASE_URL, COMMIT)[0]
        self.assertIn("story=AgencyButton.Primary", job["url"])


class LegacyManifestCompatibilityTests(unittest.TestCase):
    def legacy_manifest(self) -> dict:
        return {
            "version": 1,
            "client_id": "prototype-demo",
            "directions": ["a", "b"],
            "viewports": [
                {"name": "mobile-medium", "width": 390, "height": 844},
                {"name": "desktop", "width": 1440, "height": 900},
            ],
            "routes": [
                {"direction": "a", "path": "/?client=prototype-demo&direction=a"},
                {"direction": "b", "path": "/?client=prototype-demo&direction=b"},
            ],
        }

    def test_v1_manifest_still_normalizes(self):
        jobs = build_capture_jobs(self.legacy_manifest(), BASE_URL, COMMIT)
        self.assertEqual(4, len(jobs))
        self.assertEqual({"a", "b"}, {job["direction"] for job in jobs})
        self.assertEqual(
            {(390, 844), (1440, 900)},
            {(job["viewport"]["width"], job["viewport"]["height"]) for job in jobs},
        )

    def test_v1_normalization_produces_v2_jobs(self):
        normalized = normalize_manifest(self.legacy_manifest())
        self.assertEqual(2, normalized["version"])
        self.assertEqual(4, len(normalized["jobs"]))
        for job in normalized["jobs"]:
            self.assertEqual("prototype", job["surface"])
            self.assertEqual("default", job["state"])
            self.assertEqual(1, job["device_scale_factor"])

    def test_v1_capture_id_is_stable(self):
        first = build_capture_jobs(self.legacy_manifest(), BASE_URL, COMMIT)
        second = build_capture_jobs(self.legacy_manifest(), BASE_URL, COMMIT)
        self.assertEqual(
            [job["capture_id"] for job in first], [job["capture_id"] for job in second]
        )

    def test_v1_invalid_direction_is_rejected(self):
        manifest = self.legacy_manifest()
        manifest["directions"] = ["a", "z"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)

    def test_v1_missing_viewports_is_rejected(self):
        manifest = self.legacy_manifest()
        del manifest["viewports"]
        with self.assertRaises(InvalidCaptureJob):
            normalize_manifest(manifest)


SCREENS = {
    "a": ["commerce.home"],
    "b": ["commerce.plp"],
    "c": ["commerce.pdp"],
}


class ManifestWriterTests(unittest.TestCase):
    def test_build_screenshot_manifest_writes_v2(self):
        manifest = build_screenshot_manifest("prototype-demo", ["a", "b", "c"], SCREENS)
        self.assertEqual(2, manifest["version"])
        self.assertEqual("prototype-demo", manifest["client_id"])
        self.assertTrue(manifest["fixture_version"])
        self.assertEqual(15, len(manifest["jobs"]))
        self.assertEqual({"a", "b", "c"}, {job["direction"] for job in manifest["jobs"]})

    def test_build_screenshot_manifest_keeps_governed_viewports(self):
        manifest = build_screenshot_manifest(
            "prototype-demo", ["a", "b"], {"a": ["commerce.home"], "b": ["commerce.plp"]}
        )
        sizes = {(v["width"], v["height"]) for v in manifest["viewports"]}
        self.assertEqual(
            {(360, 800), (390, 844), (430, 932), (768, 1024), (1440, 900)}, sizes
        )

    def test_build_screenshot_manifest_expands_declared_screens(self):
        manifest = build_screenshot_manifest(
            "prototype-demo",
            ["a", "b"],
            screens_by_direction={"a": ["commerce.home"], "b": ["commerce.plp"]},
        )
        pairs = {(job["direction"], job["screen"]) for job in manifest["jobs"]}
        self.assertEqual({("a", "commerce.home"), ("b", "commerce.plp")}, pairs)

    def test_build_screenshot_manifest_is_validated_by_normalize(self):
        manifest = build_screenshot_manifest("prototype-demo", ["a", "b", "c"], SCREENS)
        normalized = normalize_manifest(manifest)
        self.assertEqual(15, len(normalized["jobs"]))

    def test_build_screenshot_manifest_requires_screens(self):
        with self.assertRaises(InvalidCaptureJob):
            build_screenshot_manifest("prototype-demo", ["a", "b"])


class SchemaAndDemoManifestTests(unittest.TestCase):
    def test_screenshot_manifest_schema_exists_and_is_json(self):
        self.assertTrue(SCHEMA_PATH.exists(), SCHEMA_PATH)
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertIsInstance(schema, dict)
        self.assertIn("properties", schema)

    def test_schema_requires_version_client_and_jobs(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual({"version", "client_id", "jobs"}, set(schema["required"]))

    def test_demo_manifest_is_v2_and_valid(self):
        import yaml

        data = yaml.safe_load(DEMO_MANIFEST_PATH.read_text(encoding="utf-8"))
        self.assertEqual(2, data["version"])
        normalized = normalize_manifest(data)
        self.assertTrue(normalized["jobs"])
        directions = {job["direction"] for job in normalized["jobs"]}
        self.assertTrue(directions.issubset({"a", "b", "c"}))

    def test_demo_manifest_covers_all_declared_directions(self):
        import yaml

        data = yaml.safe_load(DEMO_MANIFEST_PATH.read_text(encoding="utf-8"))
        jobs = build_capture_jobs(data, BASE_URL, COMMIT)
        self.assertEqual({"a", "b", "c"}, {job["direction"] for job in jobs})


if __name__ == "__main__":
    unittest.main()
