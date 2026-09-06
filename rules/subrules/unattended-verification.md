# Unattended Verification

Every unattended unit must prove a checkable result for its current run. An
exit code, accepted request, or running status alone is insufficient. Verify
through the owning command or service and distinguish this run's output from
leftovers.

Bound waits by expected runtime, detect missing progress, and recover stalled
work. A parked task needs a verified watcher and a completion signal; otherwise
retain active ownership. Report an unresolved result as unverified. Respect
shared quotas, avoid redundant polling, and surface genuine blocks without
routine notification noise.
