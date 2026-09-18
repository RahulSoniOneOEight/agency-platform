/// Provider-neutral health outcome of a completed release.
///
/// [healthy] means the released artifact met every gate and telemetry signal.
/// [degraded] means the release is serving traffic but at least one
/// non-blocking signal is impaired. [failed] means the release did not meet the
/// required release gates.
enum ReleaseOutcome { healthy, degraded, failed }
