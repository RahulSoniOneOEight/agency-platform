"""Deterministic visual-QA tooling: capture, contracts, goldens, providers.

Submodules are imported explicitly by callers (``from tooling.visual_qa.errors
import CaptureFailed``); this package intentionally re-exports nothing so the
import graph stays acyclic and explicit.
"""
