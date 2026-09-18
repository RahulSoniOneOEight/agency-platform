from __future__ import annotations
import argparse
from pathlib import Path
import sys
from .evidence import load_release_candidate,require_fresh_evidence
from .models import canonical_json
from .reference_client import REFERENCE_CLIENT,build_reference_candidate,candidate_freshness_errors
from .release_gate import verify_release_gate
from .repository import FileProductionAuthorizationRepository

def validate_client_authorizations(root:Path,client_dir:Path)->list[str]:
    root=Path(root); client_dir=Path(client_dir); errors=[]
    try:
        candidate=load_release_candidate(client_dir/"release"/"candidate.json"); require_fresh_evidence(candidate)
    except Exception as exc:
        return [f"production authorization candidate: {exc}"]
    if client_dir.name==REFERENCE_CLIENT:
        errors.extend(candidate_freshness_errors(root))
        try:
            if build_reference_candidate(root)!=candidate: errors.append("reference release candidate does not match merged F evidence")
        except Exception as exc: errors.append(f"reference release candidate cannot be rebuilt: {exc}")
    repo=FileProductionAuthorizationRepository(client_dir)
    try: authorizations=repo.list(candidate.client_id,candidate.environment)
    except Exception as exc: return errors+[f"production authorization repository: {exc}"]
    if not authorizations: return errors+["production authorization is missing for release candidate"]
    latest=authorizations[-1]
    auth_path=client_dir/"release"/"production-authorizations"/candidate.environment/f"authorization-v{latest.authorization_version:04d}.json"
    try:
        if auth_path.read_text(encoding="utf-8")!=canonical_json(latest): errors.append(f"{auth_path}: authorization bytes are not canonical/fresh")
    except OSError as exc: errors.append(f"{auth_path}: cannot read authorization: {exc}")
    try: verify_release_gate(latest,candidate)
    except Exception as exc: errors.append(f"production release gate: {exc}")
    for ref in (candidate.rollback_plan_ref,candidate.release_notes_ref,candidate.migration_plan_ref,*candidate.supporting_evidence_refs):
        if ref and not (root/ref).exists(): errors.append(f"production release evidence ref missing: {ref}")
    return sorted(set(errors))

def main(argv:list[str]|None=None)->int:
    parser=argparse.ArgumentParser(description="Validate Milestone G production authorization")
    parser.add_argument("client_dir",nargs="?",default="client-projects/reference-commerce"); args=parser.parse_args(argv)
    root=Path(__file__).resolve().parents[2]; client_dir=Path(args.client_dir)
    if not client_dir.is_absolute(): client_dir=root/client_dir
    errors=validate_client_authorizations(root,client_dir)
    if errors:
        print("Production authorization validation failed.")
        for error in errors: print(f"- {error}")
        return 1
    print("Production authorization validation passed: exact candidate/environment is human-authorized and evidence is fresh.")
    return 0
if __name__=="__main__": sys.exit(main())
