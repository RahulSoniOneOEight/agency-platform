from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ClientPaths:
    client_dir: Path

    @classmethod
    def for_client(cls, client_dir: Path) -> "ClientPaths":
        return cls(client_dir=client_dir)

    @property
    def brief(self) -> Path:
        return self.client_dir / "brief.md"

    @property
    def workflow_state(self) -> Path:
        return self.client_dir / "workflow-state.yaml"

    @property
    def input_dir(self) -> Path:
        return self.client_dir / "input"

    @property
    def client_input(self) -> Path:
        return self.input_dir / "client-input.yaml"

    @property
    def derived_dir(self) -> Path:
        return self.client_dir / "derived"

    @property
    def client_profile(self) -> Path:
        return self.derived_dir / "client-profile.yaml"

    @property
    def resolved_presets(self) -> Path:
        return self.derived_dir / "resolved-presets.yaml"

    @property
    def intelligence_map(self) -> Path:
        return self.derived_dir / "intelligence-map.yaml"

    @property
    def capability_map(self) -> Path:
        return self.derived_dir / "capability-map.yaml"

    @property
    def gaps(self) -> Path:
        return self.derived_dir / "gaps.yaml"

    @property
    def resource_requirements(self) -> Path:
        return self.derived_dir / "resource-requirements.yaml"

    @property
    def resource_selection(self) -> Path:
        return self.client_dir / "resources" / "selection.yaml"

    def read_client_profile(self) -> Path:
        if self.client_profile.exists():
            return self.client_profile
        legacy = self.client_dir / "client-profile.yaml"
        return legacy if legacy.exists() else self.client_profile

    def read_resolved_presets(self) -> Path:
        if self.resolved_presets.exists():
            return self.resolved_presets
        legacy = self.client_dir / "resolved-intelligence.yaml"
        return legacy if legacy.exists() else self.resolved_presets

    def has_client_input_for_migration(self) -> bool:
        return self.client_input.exists() or (self.client_dir / "client-profile.yaml").exists()

    def has_derived_intelligence_for_migration(self) -> bool:
        canonical = (
            self.resolved_presets,
            self.intelligence_map,
            self.capability_map,
            self.gaps,
        )
        if all(path.exists() for path in canonical):
            return True
        return (self.client_dir / "resolved-intelligence.yaml").exists()
