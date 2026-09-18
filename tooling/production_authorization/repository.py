from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .errors import ProductionAuthorizationVersionConflict
from .models import ProductionAuthorization, canonical_json


class ProductionAuthorizationRepository(Protocol):
    def list(self, client_id: str, environment: str) -> list[ProductionAuthorization]: ...
    def create(self, authorization: ProductionAuthorization) -> Path: ...


class FileProductionAuthorizationRepository:
    """Append-only repository rooted at a client project's release directory."""

    def __init__(self, client_dir: Path):
        self.client_dir = Path(client_dir)

    def _directory(self, environment: str) -> Path:
        return self.client_dir / "release" / "production-authorizations" / environment

    def list(self, client_id: str, environment: str) -> list[ProductionAuthorization]:
        directory = self._directory(environment)
        if not directory.exists():
            return []
        records: list[ProductionAuthorization] = []
        for path in sorted(directory.glob("authorization-v*.json")):
            import json
            record = ProductionAuthorization.from_dict(json.loads(path.read_text(encoding="utf-8")))
            if record.client_id != client_id or record.environment != environment:
                raise ProductionAuthorizationVersionConflict(
                    f"authorization file {path} does not belong to {client_id}/{environment}"
                )
            records.append(record)
        records.sort(key=lambda item: item.authorization_version)
        return records

    def create(self, authorization: ProductionAuthorization) -> Path:
        directory = self._directory(authorization.environment)
        directory.mkdir(parents=True, exist_ok=True)
        existing = self.list(authorization.client_id, authorization.environment)
        if any(item.authorization_version == authorization.authorization_version for item in existing):
            raise ProductionAuthorizationVersionConflict(
                f"authorization version {authorization.authorization_version} already exists "
                f"for {authorization.client_id}/{authorization.environment}"
            )
        if existing and authorization.authorization_version != existing[-1].authorization_version + 1:
            raise ProductionAuthorizationVersionConflict(
                "authorization versions must be monotonic without gaps"
            )
        if not existing and authorization.authorization_version != 1:
            raise ProductionAuthorizationVersionConflict(
                "first authorization version must be 1"
            )
        path = directory / f"authorization-v{authorization.authorization_version:04d}.json"
        try:
            with path.open("x", encoding="utf-8", newline="\n") as handle:
                handle.write(canonical_json(authorization))
        except FileExistsError as exc:
            raise ProductionAuthorizationVersionConflict(
                f"authorization path already exists: {path}"
            ) from exc
        return path
