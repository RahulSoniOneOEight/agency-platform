"""Compatibility CLI for deterministic screenshot capture.

This module preserves the historical entry point
(``python -m tooling.prototype.capture_screenshots``) while delegating all real
work to the D.1 capture package:

    manifest -> normalized v2 jobs -> ScreenshotCaptureBackend -> ScreenshotArtifact

Generated PNGs and sidecar metadata are build/QA artifacts; they are written
only under ``--out`` and never into runtime bundles or governed baselines.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml

from tooling.visual_qa.capture_runner import CaptureRunner, ProcessCaptureBackend
from tooling.visual_qa.errors import VisualQaError

from .screenshot_manifest import build_capture_jobs as _build_capture_jobs


def build_capture_jobs(manifest: dict, base_url: str = "http://localhost:8080") -> list[dict]:
    """Backwards-compatible wrapper around the v2 capture-job builder."""
    return _build_capture_jobs(manifest, base_url, "")


def load_capture_jobs(path: Path, base_url: str = "http://localhost:8080") -> list[dict]:
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("screenshot manifest must be a mapping")
    return build_capture_jobs(data, base_url)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="capture_screenshots",
        description=(
            "Capture governed screenshots from a deterministic v1/v2 screenshot "
            "manifest. Generated images are QA/build artifacts."
        ),
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(
            "client-projects/examples/prototype-demo/prototype/qa/screenshot-manifest.yaml"
        ),
        help="Path to the client screenshot manifest (v1 or v2).",
    )
    parser.add_argument(
        "--base-url",
        default="http://localhost:8080",
        help="Base URL of the running Flutter web prototype or Widgetbook.",
    )
    parser.add_argument(
        "--commit",
        default="",
        help="Source commit SHA captured by these jobs (recorded in artifact identity).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("build/visual-qa/screenshots"),
        help="Output directory for generated PNGs and sidecar metadata.",
    )
    parser.add_argument(
        "--browser-script",
        type=Path,
        default=None,
        help="Override the transport-only headless-browser adapter path.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the resolved capture jobs without capturing anything.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    data = yaml.safe_load(args.manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print("screenshot manifest must be a mapping", file=sys.stderr)
        return 2

    try:
        jobs = _build_capture_jobs(data, args.base_url, args.commit)
    except VisualQaError as error:
        print(f"{error.code}: {error.message}", file=sys.stderr)
        return 2

    if args.dry_run:
        print(json.dumps(jobs, indent=2, sort_keys=True))
        return 0

    backend = ProcessCaptureBackend(args.browser_script)
    if not backend.available():
        print(
            "capture_failed: browser adapter unavailable "
            f"({backend.script_path}). "
            "Install a local headless browser driver; see VISUAL_QA.md.",
            file=sys.stderr,
        )
        return 3

    runner = CaptureRunner(backend=backend, output_dir=args.out)
    try:
        artifacts = runner.run(jobs)
    except VisualQaError as error:
        print(f"{error.code}: {error.message}", file=sys.stderr)
        return 4

    for artifact in artifacts:
        print(artifact.path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
