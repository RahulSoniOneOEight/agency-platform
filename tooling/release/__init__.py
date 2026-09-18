"""H.2 authorized-release bridge tooling (Milestone H.2, Task 8).

This package bridges the frozen H.2 release candidate to the existing Milestone-G
``ProductionAuthorization`` authority (spec sections 4, 7, 9, 22 and acceptance
criteria 13, 14, 39, 41, 42).

Authority boundary
------------------
H.2 may *read* and *verify* a ``ProductionAuthorization`` but must never create,
mutate, or substitute for one. Nothing in this package constructs a
``ProductionAuthorization`` and nothing imports the G coordinator or the
authorization repository's ``create`` path: the human release owner is the only
authority that produces an authorization. The exact H.2 reference authorization
is committed data, generated outside this package.

The single public bridge entry point is
:func:`tooling.release.coordinator.verify_h2_authorized_candidate`, which
delegates all G validity semantics to the existing
``tooling.production_authorization.release_gate.verify_release_gate`` and then
checks only the H.2-specific candidate bindings.
"""
