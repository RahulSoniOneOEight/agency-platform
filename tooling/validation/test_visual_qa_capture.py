from __future__ import annotations

import contextlib
import io
import json
import os
import shutil
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

import yaml

from tooling.prototype.screenshot_manifest import (
    MANIFEST_VERSION,
    STANDARD_VIEWPORTS,
    InvalidCaptureJob,
    build_capture_jobs,
    build_screenshot_manifest,
    normalize_manifest,
)
from tooling.visual_qa.capture_models import ScreenshotArtifact
from tooling.visual_qa.capture_runner import (
    CaptureResult,
    CaptureRunner,
    png_dimensions,
)
from tooling.visual_qa.errors import (
    CaptureFailed,
    CaptureNotDeterministic,
    InvalidScreenshotMetadata,
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

    def test_scale_factor_numeric_equivalence(self):
        integer = build_capture_jobs(
            v2_manifest(job={"device_scale_factor": 1}), BASE_URL, COMMIT
        )[0]
        floating = build_capture_jobs(
            v2_manifest(job={"device_scale_factor": 1.0}), BASE_URL, COMMIT
        )[0]
        self.assertEqual(integer["capture_id"], floating["capture_id"])
        self.assertEqual(integer["filename"], floating["filename"])

    def test_viewport_name_is_part_of_identity(self):
        named = build_capture_jobs(
            v2_manifest(job={"viewport": {"name": "mobile-medium"}}), BASE_URL, COMMIT
        )[0]
        explicit = build_capture_jobs(
            v2_manifest(job={"viewport": {"width": 390, "height": 844}}),
            BASE_URL,
            COMMIT,
        )[0]
        self.assertNotEqual(named["capture_id"], explicit["capture_id"])
        self.assertNotEqual(named["filename"], explicit["filename"])

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

    def test_hostile_state_is_sanitized_in_the_filename(self):
        job = build_capture_jobs(
            v2_manifest(job={"state": "loading/error"}), BASE_URL, COMMIT
        )[0]
        for unsafe in ("/", "\\", ":", "?", "*", '"', "<", ">", "|"):
            self.assertNotIn(unsafe, job["filename"])


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

    def test_route_carries_a_non_default_state(self):
        job = build_capture_jobs(
            v2_manifest(job={"state": "loading"}), BASE_URL, COMMIT
        )[0]
        self.assertIn("state=loading", job["url"])

    def test_default_state_is_not_forced_into_the_route(self):
        job = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)[0]
        self.assertNotIn("state=", job["url"])

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


FIXED_CLOCK = datetime(2026, 9, 17, 12, 0, 0, tzinfo=timezone.utc)


def png_bytes(width: int, height: int) -> bytes:
    """A structurally parseable PNG header carrying explicit dimensions."""
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = (
        width.to_bytes(4, "big")
        + height.to_bytes(4, "big")
        + b"\x08\x06\x00\x00\x00"
    )
    chunk = len(ihdr).to_bytes(4, "big") + b"IHDR" + ihdr + b"\x00\x00\x00\x00"
    return signature + chunk + b"\x00\x00\x00\x00IEND\xaeB`\x82"


class FakeBackend:
    """Writes deterministic bytes for every job."""

    def __init__(self, payload: bytes) -> None:
        self.payload = payload
        self.calls: list[tuple[str, str]] = []

    def capture(self, job: dict, destination: Path) -> CaptureResult:
        self.calls.append((job["capture_id"], job["url"]))
        destination.write_bytes(self.payload)
        return CaptureResult()


class FailingBackend:
    def capture(self, job: dict, destination: Path) -> CaptureResult:
        raise CaptureFailed("browser launch failed")


class EmptyBackend:
    def capture(self, job: dict, destination: Path) -> CaptureResult:
        destination.write_bytes(b"")
        return CaptureResult()


class MissingOutputBackend:
    def capture(self, job: dict, destination: Path) -> CaptureResult:
        return CaptureResult()


class PartialThenFailBackend:
    def capture(self, job: dict, destination: Path) -> CaptureResult:
        destination.write_bytes(b"\x89PNG\r\n\x1a\npartial")
        raise CaptureFailed("navigation timed out")


class NondeterministicBackend:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload

    def capture(self, job: dict, destination: Path) -> CaptureResult:
        destination.write_bytes(self.payload)
        return CaptureResult(deterministic=False, detail="animation still settling")


def sample_job(**overrides: object) -> dict:
    job = build_capture_jobs(v2_manifest(), BASE_URL, COMMIT)[0]
    job.update(overrides)
    return job


class CaptureRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.output_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def runner(self, backend: object, **kwargs: object) -> CaptureRunner:
        return CaptureRunner(
            backend=backend,
            output_dir=self.output_dir,
            clock=lambda: FIXED_CLOCK,
            **kwargs,
        )

    def test_runner_persists_no_success_for_failed_capture(self):
        with self.assertRaises(CaptureFailed):
            self.runner(FailingBackend()).run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))
        self.assertEqual([], list(self.output_dir.glob("*.png")))
        self.assertEqual([], list(self.output_dir.glob("*.tmp")))

    def test_partial_capture_is_not_published(self):
        with self.assertRaises(CaptureFailed):
            self.runner(PartialThenFailBackend()).run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))
        self.assertEqual([], list(self.output_dir.glob("*.png")))

    def test_empty_capture_is_rejected(self):
        with self.assertRaises(CaptureFailed):
            self.runner(EmptyBackend()).run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))

    def test_non_png_capture_is_rejected(self):
        with self.assertRaises(CaptureFailed):
            self.runner(FakeBackend(b"not a png at all")).run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))
        self.assertEqual([], list(self.output_dir.glob("*.png")))

    def test_sidecar_failure_does_not_orphan_the_png(self):
        import unittest.mock as mock

        from tooling.visual_qa import capture_runner

        real_replace = os.replace
        calls = {"count": 0}

        def flaky_replace(source, destination):
            calls["count"] += 1
            if calls["count"] == 2:
                raise OSError("sidecar publish failed")
            return real_replace(source, destination)

        runner = self.runner(FakeBackend(png_bytes(390, 844)))
        with mock.patch.object(capture_runner.os, "replace", side_effect=flaky_replace):
            with self.assertRaises(OSError):
                runner.run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.png")))
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))

    def test_missing_capture_output_is_rejected(self):
        with self.assertRaises(CaptureFailed):
            self.runner(MissingOutputBackend()).run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))

    def test_nondeterministic_capture_is_rejected(self):
        with self.assertRaises(CaptureNotDeterministic):
            self.runner(NondeterministicBackend(png_bytes(390, 844))).run(
                [sample_job()]
            )
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))

    def test_artifact_identity_matches_job_and_hash(self):
        job = sample_job()
        artifacts = self.runner(FakeBackend(png_bytes(390, 844))).run([job])
        self.assertEqual(1, len(artifacts))
        artifact = artifacts[0]
        self.assertEqual(job["capture_id"], artifact.capture_id)
        self.assertTrue(artifact.content_hash.startswith("sha256:"))
        self.assertEqual(64, len(artifact.content_hash.split(":", 1)[1]))

    def test_artifact_records_full_reproducibility_identity(self):
        job = sample_job(mix_ref="review-state-v2")
        artifact = self.runner(FakeBackend(png_bytes(390, 844))).run([job])[0]
        self.assertEqual("prototype-demo", artifact.client_id)
        self.assertEqual("prototype", artifact.surface)
        self.assertEqual("commerce.home", artifact.screen)
        self.assertIsNone(artifact.story)
        self.assertEqual("default", artifact.state)
        self.assertEqual("b", artifact.direction)
        self.assertEqual("review-state-v2", artifact.mix_ref)
        self.assertEqual(390, artifact.viewport["width"])
        self.assertEqual(844, artifact.viewport["height"])
        self.assertEqual(1, artifact.device_scale_factor)
        self.assertEqual("demo-v1", artifact.fixture_version)
        self.assertEqual(COMMIT, artifact.source_commit_sha)
        self.assertEqual(job["url"], artifact.url)
        self.assertEqual(job["filename"], artifact.filename)

    def test_artifact_writes_png_and_sidecar(self):
        job = sample_job()
        artifact = self.runner(FakeBackend(png_bytes(390, 844))).run([job])[0]
        png = self.output_dir / job["filename"]
        sidecar = self.output_dir / f"{job['filename']}.artifact.json"
        self.assertTrue(png.exists())
        self.assertTrue(sidecar.exists())
        self.assertEqual(job["filename"], artifact.path)
        payload = json.loads(sidecar.read_text(encoding="utf-8"))
        self.assertEqual(artifact.to_json(), payload)

    def test_artifact_dimensions_are_read_from_the_capture(self):
        artifact = self.runner(FakeBackend(png_bytes(390, 844))).run(
            [sample_job()]
        )[0]
        self.assertEqual(390, artifact.width)
        self.assertEqual(844, artifact.height)

    def test_artifact_rejects_dimension_mismatch(self):
        with self.assertRaises(InvalidScreenshotMetadata):
            self.runner(FakeBackend(png_bytes(200, 200))).run([sample_job()])
        self.assertEqual([], list(self.output_dir.glob("*.artifact.json")))

    def test_runner_returns_artifacts_in_job_order(self):
        manifest = v2_manifest()
        manifest["jobs"] = [
            manifest["jobs"][0],
            {
                "surface": "prototype",
                "screen": "commerce.search",
                "state": "default",
                "direction": "b",
                "viewport": {"width": 390, "height": 844},
            },
        ]
        jobs = build_capture_jobs(manifest, BASE_URL, COMMIT)
        backend = FakeBackend(png_bytes(390, 844))
        artifacts = self.runner(backend).run(jobs)
        self.assertEqual(
            [job["capture_id"] for job in jobs],
            [artifact.capture_id for artifact in artifacts],
        )
        self.assertEqual(2, len(backend.calls))

    def test_artifact_metadata_is_reproducible_across_runs(self):
        payload = png_bytes(390, 844)
        first = self.runner(FakeBackend(payload)).run([sample_job()])[0]
        second_dir = Path(self._tmp.name) / "second"
        second = CaptureRunner(
            backend=FakeBackend(payload),
            output_dir=second_dir,
            clock=lambda: FIXED_CLOCK,
        ).run([sample_job()])[0]
        self.assertEqual(first.to_json(), second.to_json())
        self.assertEqual(first.captured_at, second.captured_at)

    def test_runner_does_not_mutate_jobs(self):
        job = sample_job()
        before = json.dumps(job, sort_keys=True)
        self.runner(FakeBackend(png_bytes(390, 844))).run([job])
        self.assertEqual(before, json.dumps(job, sort_keys=True))

    def test_runner_writes_only_inside_the_output_directory(self):
        before = sorted(p.name for p in self.output_dir.parent.iterdir())
        self.runner(FakeBackend(png_bytes(390, 844))).run([sample_job()])
        after = sorted(p.name for p in self.output_dir.parent.iterdir())
        self.assertEqual(before, after)

    def test_sidecar_is_pretty_printed_with_trailing_newline(self):
        job = sample_job()
        self.runner(FakeBackend(png_bytes(390, 844))).run([job])
        raw = (self.output_dir / f"{job['filename']}.artifact.json").read_text(
            encoding="utf-8"
        )
        self.assertTrue(raw.endswith("\n"))
        self.assertIn("\n  ", raw)


class ScreenshotArtifactTests(unittest.TestCase):
    def artifact_json(self) -> dict:
        job = sample_job()
        return ScreenshotArtifact.from_capture_job(
            job,
            path=job["filename"],
            content_hash="sha256:" + "a" * 64,
            width=390,
            height=844,
            captured_at=FIXED_CLOCK.isoformat(),
        ).to_json()

    def test_serialization_round_trip(self):
        payload = self.artifact_json()
        self.assertEqual(payload, ScreenshotArtifact.from_json(payload).to_json())

    def test_requires_capture_id(self):
        payload = self.artifact_json()
        del payload["capture_id"]
        with self.assertRaises(InvalidScreenshotMetadata):
            ScreenshotArtifact.from_json(payload)

    def test_requires_content_hash(self):
        payload = self.artifact_json()
        payload["content_hash"] = "not-a-hash"
        with self.assertRaises(InvalidScreenshotMetadata):
            ScreenshotArtifact.from_json(payload)

    def test_requires_source_commit(self):
        payload = self.artifact_json()
        del payload["source_commit_sha"]
        with self.assertRaises(InvalidScreenshotMetadata):
            ScreenshotArtifact.from_json(payload)

    def test_requires_viewport(self):
        payload = self.artifact_json()
        del payload["viewport"]
        with self.assertRaises(InvalidScreenshotMetadata):
            ScreenshotArtifact.from_json(payload)


class PngDimensionsTests(unittest.TestCase):
    def test_reads_dimensions(self):
        self.assertEqual((390, 844), png_dimensions(png_bytes(390, 844)))

    def test_returns_none_for_non_png(self):
        self.assertIsNone(png_dimensions(b"not a png"))
        self.assertIsNone(png_dimensions(b""))


NODE = shutil.which("node")


class ProcessCaptureBackendTests(unittest.TestCase):
    """The browser adapter contract is transport-only and JSON-typed."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def script(self, body: str) -> Path:
        path = self.tmp / "adapter.mjs"
        path.write_text(body, encoding="utf-8")
        return path

    def test_missing_adapter_script_is_a_typed_failure(self):
        from tooling.visual_qa.capture_runner import ProcessCaptureBackend

        backend = ProcessCaptureBackend(self.tmp / "does-not-exist.mjs")
        self.assertFalse(backend.available())
        with self.assertRaises(CaptureFailed):
            backend.capture(sample_job(), self.tmp / "out.png")

    @unittest.skipIf(NODE is None, "node is not installed")
    def test_successful_adapter_capture_is_published(self):
        from tooling.visual_qa.capture_runner import ProcessCaptureBackend

        payload = png_bytes(390, 844)
        script = self.script(
            "import { writeFileSync } from 'node:fs';\n"
            "const out = process.argv[process.argv.indexOf('--out') + 1];\n"
            f"writeFileSync(out, Buffer.from('{payload.hex()}', 'hex'));\n"
            "process.stdout.write(JSON.stringify({ok:true,deterministic:true}) + '\\n');\n"
        )
        backend = ProcessCaptureBackend(script, node=NODE or "node")
        artifacts = CaptureRunner(
            backend=backend, output_dir=self.tmp / "out", clock=lambda: FIXED_CLOCK
        ).run([sample_job()])
        self.assertEqual(1, len(artifacts))
        self.assertEqual(390, artifacts[0].width)

    @unittest.skipIf(NODE is None, "node is not installed")
    def test_adapter_failure_maps_to_capture_failed(self):
        from tooling.visual_qa.capture_runner import ProcessCaptureBackend

        script = self.script(
            "process.stdout.write(JSON.stringify({ok:false,code:'capture_failed',"
            "message:'navigation failed'}) + '\\n');\n"
            "process.exit(1);\n"
        )
        backend = ProcessCaptureBackend(script, node=NODE or "node")
        with self.assertRaises(CaptureFailed):
            backend.capture(sample_job(), self.tmp / "out.png")

    @unittest.skipIf(NODE is None, "node is not installed")
    def test_adapter_nondeterminism_maps_to_typed_error(self):
        from tooling.visual_qa.capture_runner import ProcessCaptureBackend

        script = self.script(
            "process.stdout.write(JSON.stringify({ok:false,"
            "code:'capture_not_deterministic',message:'animation settling'}) + '\\n');\n"
            "process.exit(1);\n"
        )
        backend = ProcessCaptureBackend(script, node=NODE or "node")
        with self.assertRaises(CaptureNotDeterministic):
            backend.capture(sample_job(), self.tmp / "out.png")

    @unittest.skipIf(NODE is None, "node is not installed")
    def test_adapter_without_json_output_is_a_typed_failure(self):
        from tooling.visual_qa.capture_runner import ProcessCaptureBackend

        script = self.script("process.stdout.write('not json\\n');\n")
        backend = ProcessCaptureBackend(script, node=NODE or "node")
        with self.assertRaises(CaptureFailed):
            backend.capture(sample_job(), self.tmp / "out.png")


class CaptureCliTests(unittest.TestCase):
    def test_parser_exposes_governed_flags(self):
        from tooling.prototype.capture_screenshots import build_parser

        parser = build_parser()
        options = {action.dest for action in parser._actions}
        self.assertTrue(
            {"manifest", "base_url", "commit", "out", "dry_run"}.issubset(options)
        )

    def test_dry_run_lists_jobs_without_capturing(self):
        from tooling.prototype import capture_screenshots

        manifest = self._write_manifest()
        out = Path(tempfile.mkdtemp()) / "screens"
        with contextlib.redirect_stdout(io.StringIO()) as buffer:
            code = capture_screenshots.main(
                [
                    "--manifest",
                    str(manifest),
                    "--commit",
                    COMMIT,
                    "--out",
                    str(out),
                    "--dry-run",
                ]
            )
        self.assertEqual(0, code)
        jobs = json.loads(buffer.getvalue())
        self.assertEqual(1, len(jobs))
        self.assertEqual(COMMIT, jobs[0]["source_commit_sha"])
        self.assertFalse(out.exists())

    def test_missing_browser_adapter_is_a_typed_cli_failure(self):
        from tooling.prototype import capture_screenshots

        manifest = self._write_manifest()
        with contextlib.redirect_stderr(io.StringIO()) as buffer:
            code = capture_screenshots.main(
                [
                    "--manifest",
                    str(manifest),
                    "--commit",
                    COMMIT,
                    "--out",
                    str(Path(tempfile.mkdtemp()) / "screens"),
                    "--browser-script",
                    str(Path(tempfile.mkdtemp()) / "absent.mjs"),
                ]
            )
        self.assertEqual(3, code)
        self.assertIn("capture_failed", buffer.getvalue())

    def test_invalid_manifest_is_a_typed_cli_failure(self):
        from tooling.prototype import capture_screenshots

        manifest = Path(tempfile.mkdtemp()) / "manifest.yaml"
        manifest.write_text(
            "version: 2\nclient_id: demo\nfixture_version: v1\njobs:\n- surface: prototype\n"
            "  screen: commerce.home\n  state: default\n  direction: z\n"
            "  viewport: {width: 390, height: 844}\n",
            encoding="utf-8",
        )
        with contextlib.redirect_stderr(io.StringIO()) as buffer:
            code = capture_screenshots.main(
                ["--manifest", str(manifest), "--dry-run"]
            )
        self.assertEqual(2, code)
        self.assertIn("invalid_capture_job", buffer.getvalue())

    def _write_manifest(self) -> Path:
        manifest = Path(tempfile.mkdtemp()) / "manifest.yaml"
        manifest.write_text(
            yaml.safe_dump(v2_manifest(), sort_keys=False), encoding="utf-8"
        )
        return manifest


class ClientVisualQaValidatorTests(unittest.TestCase):
    def test_demo_client_passes(self):
        from tooling.prototype.validate_visual_qa import validate_client_visual_qa

        root = Path(__file__).resolve().parents[2]
        errors = validate_client_visual_qa(
            root / "client-projects" / "examples" / "prototype-demo"
        )
        self.assertEqual([], errors)

    def test_invalid_manifest_is_reported(self):
        from tooling.prototype.validate_visual_qa import validate_client_visual_qa

        client = Path(tempfile.mkdtemp()) / "acme"
        qa = client / "prototype" / "qa"
        qa.mkdir(parents=True)
        (qa / "screenshot-manifest.yaml").write_text(
            yaml.safe_dump(v2_manifest(job={"direction": "z"}), sort_keys=False),
            encoding="utf-8",
        )
        errors = validate_client_visual_qa(client)
        self.assertTrue(any("invalid screenshot manifest" in error for error in errors), errors)

    def test_missing_manifest_is_reported(self):
        from tooling.prototype.validate_visual_qa import validate_client_visual_qa

        client = Path(tempfile.mkdtemp()) / "acme"
        (client / "prototype").mkdir(parents=True)
        errors = validate_client_visual_qa(client)
        self.assertTrue(any("missing screenshot manifest" in error for error in errors), errors)

    def test_legacy_findings_are_still_validated(self):
        from tooling.prototype.validate_visual_qa import validate_client_visual_qa

        client = Path(tempfile.mkdtemp()) / "acme"
        qa = client / "prototype" / "qa"
        qa.mkdir(parents=True)
        (qa / "screenshot-manifest.yaml").write_text(
            yaml.safe_dump(v2_manifest(), sort_keys=False), encoding="utf-8"
        )
        (qa / "visual-findings.yaml").write_text(
            "client_id: acme\nfindings:\n- screen: home\n", encoding="utf-8"
        )
        errors = validate_client_visual_qa(client)
        self.assertTrue(any("missing field" in error for error in errors), errors)

    def test_main_returns_nonzero_on_error(self):
        from tooling.prototype import validate_visual_qa

        client = Path(tempfile.mkdtemp()) / "acme"
        (client / "prototype").mkdir(parents=True)
        with contextlib.redirect_stdout(io.StringIO()) as buffer:
            code = validate_visual_qa.main([str(client)])
        self.assertEqual(1, code)
        self.assertIn("Visual QA validation failed", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()
