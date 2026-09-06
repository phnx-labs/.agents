# Remote Dispatch

Use the native `--device` dispatch path and the `run`/`teams` skills; launching
`agents run` inside an open SSH command can leave it waiting on stdin.

Verify the target can perform the actual operation with the selected harness;
a read-only login probe does not prove write capability. Base placement on
current availability, not remembered failures. Use supported session/device
status commands and bounded completion checks (`unattended-verification`).
