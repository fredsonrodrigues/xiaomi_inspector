# Unified Xiaomi workflow — 2026-11-11

Status: completed on eos, with network settings explicitly pending.

## Interface

```sh
./xiaomi_inspector.sh --out results/my_phone_run
```

One workflow identifies the phone, scans, plans, confirms, applies, reboots,
waits for idle, verifies, and reports. `run`, `all`, and `full` invoke the same
implementation. `--yes` explicitly accepts cleanup and reboot for an approved
unattended run. `scan` remains read-only.

The current profile is shared across Xiaomi, Redmi, and POCO manufacturers.
Manufacturer detection replaces the old `platina`-only gate. Model names do not
change the workflow; package presence, the generated plan, and the detected home
activity determine applicable actions.

## Changes driven by the eos test

- Skip absent apps in appops and verification.
- Resolve the default home activity rather than require `com.miui.home`.
- Apply package removals only when present and marked for removal in the plan.
- Protect ChordBot, matching the owner's existing decision.
- Verify preservation against all initially enabled packages minus recorded
  removals instead of requiring a fixed sample from the original phone.
- Preserve the previous appops mode in rollback/restoration, and scope appops
  to user 0.
- Bind results to the device serial; refuse a different device's results and
  prevent rescanning a folder with an existing cleanup log.
- Propagate failed stages instead of continuing to report success.
- Expose ADB daemon failures instead of misreporting them as an absent phone.

## Local regression checks

`ruby tests/workflow_test.rb`: seven tests, 48 assertions, no failures.
The tests simulate both `eos` and `platina`, confirm identical default workflow
behavior, preserve ChordBot, exercise both legacy aliases, reject unsupported
manufacturers, reject results belonging to another serial, preserve a package
whose removal is refused, skip completed groups on resume, and report a network
permission denial as pending.
Invalid inventories also stop the workflow before planning or application.

Shell/Ruby syntax validation and `git diff --check` also passed.

## Live execution

Device: Xiaomi model `22011119UY`, codename `eos`, serial `4b6092120512`.

The first diagnostic scan finished, but its parent shell was interrupted by an
edit to its source while it was running (`_plan: command not found`, then the
old model guard). No cleanup occurred during that attempt. The corrected source
was syntax-checked before starting a new run.

```sh
./xiaomi_inspector.sh --out results/eos_20261111_run --yes
```

The scan found 412 enabled packages. Complete execution artifacts are local in
`results/eos_20261111_run/`; they are excluded from version control.

### Findings during application

1. Group A changed Brave from `allow` to `deny` for installation requests.
   The other three apps already denied the operation.
2. Cache trimming increased reported free storage from 35,522,684 KiB to
   45,673,348 KiB (approximately 9.68 GiB).
3. Groups B, D, and C1 completed and passed launcher validation.
4. ShareMe (`com.xiaomi.midrop`) returned `Failure [-1000]` and remained
   installed. The first run stopped at C2 with exit 60. The adapted workflow
   records this specific refusal in `skipped.txt` and preserves the app.
   Other removal errors remain fatal. No disable/root workaround was attempted.
5. Resuming skipped completed groups and removed `com.milink.service`.
6. Group E failed its first write with `WRITE_SECURE_SETTINGS` permission denial,
   before any network setting changed. The first attempt exited 70 and attempted
   restoration. The adapted workflow records this denial as a pending manual
   task, preserves network settings, and continues to reboot and verification.

Neither the meaning of firmware error `-1000` nor the underlying cause of the
settings permission restriction was established. The adaptations rely on the
observed response and subsequent package presence, rather than an assumed
device-specific workaround.

The run was resumed using the same public entry point:

```sh
./xiaomi_inspector.sh --out results/eos_20261111_run --resume --yes
```

Ten packages were removed from user 0: CAIXA, My Vodafone, Google Photos, MIUI
System Ads, Xiaomi Analytics, Mi Cloud Backup, Mi Cloud Sync, Mi Cloud Service,
Xiaomi Payment, and MiLink. Exact package names and restoration commands are in
`removed.txt` and `restore.sh` in the run directory.

DNS AdGuard and Wi-Fi/BLE scanning changes remain **pending**, not successful.
They can be configured manually through Android Settings. On another firmware,
the same workflow attempts group E and validates it if ADB permits the writes.

### Final result

The resumed workflow exited 0 and emitted `VERIFICACAO_OK` after reboot and two
minutes of idle. The report confirmed all ten recorded removals and the presence
of all 402 other initially enabled packages, with no package discrepancies.
Initial free space: 35,522,684 KiB; final free space: 48,002,452 KiB, an observed
increase of approximately 11.90 GiB. Wi-Fi scanning and BLE scanning remain `1`;
Private DNS mode/specifier remain `null`. The summary explicitly lists both the
preserved ShareMe package and pending network group.

Future full runs with no `--out` create `results/run_DATE_TIME_PID/` automatically;
individual stages retain the `results/` default. Resuming requires the original
output folder. No live `platina` run was performed during this session; its shared
workflow path was exercised with simulated ADB in regression tests.

Package-presence checks do not test app behavior. Calls, banking login, 2FA,
camera, and other interactive features still require manual use of the phone.

### Follow-up: captured ShareMe refusal

On 2026-11-11, at the user's request, all accessible system logcat buffers were
captured while repeating the approved ShareMe uninstall. It again returned
`Failure [-1000]`; the package remained installed. The live capture was then
stopped without clearing the device log buffers.

The decisive line at device log time 22:23:27.422 was:

```text
D PKMSImpl: MIUILOG- can't uninstall pkg : com.xiaomi.midrop callingUid : 2000
```

This establishes an explicit refusal in MIUI's package-management layer for
the ShareMe request made by ADB shell (UID 2000). The internal policy condition
and manufacturer's rationale remain unknown. The evidence does not establish
that the app is essential or that uninstalling through Settings is blocked.

Full capture, filtered extract, exact command output, package-presence check,
and diagnosis are saved locally in
`results/eos_20261111_run/shareme_diagnostic/`. The capture contains 303 lines;
share `relevant_log.txt` instead of unrelated system/application metadata in
the complete log.

### Follow-up: ShareMe disabling accepted

At the user's explicit request, `pm disable-user --user 0 com.xiaomi.midrop`
was tested on the same eos. It exited 0 with
`Package com.xiaomi.midrop new state: disabled-user`.
The disabled-package list includes ShareMe, and dumpsys confirms
`installed=true enabled=3` for user 0 (previously `enabled=0`, default).

Thus this device blocks the observed ADB uninstall request but accepts disabling
ShareMe for user 0. The package remains installed. No reboot or interactive
sharing tests were performed after disabling. Evidence and re-enabling guidance
are in `results/eos_20261111_run/shareme_disable_test/diagnosis.md`.
This was a separate authorized diagnostic change; no automatic disable fallback
was added to the workflow or to the original run's restoration scripts.

### Implemented workaround: disable ShareMe when ADB uninstall is refused

Following the successful manual disable test, the user requested integrating
the action into the program. The workflow now attempts `pm disable-user --user 0
com.xiaomi.midrop` only when its approved uninstall returns exactly
`Failure [-1000]` and the app is confirmed installed. Other apps retain the
previous skip behavior for that error; other uninstall errors remain fatal.

The fallback reads the previous user-0 enabled state, verifies the disabled
package list after the command, and validates the launcher with the group. A
failure attempts to restore the prior enabled state and stops the group. A
later failure in the same group also rolls back the fallback. Successfully
disabled packages are recorded separately in `disabled.txt`, not `removed.txt`.
Restoration scripts use the matching state command (`default-state`, `enable`,
etc.). An already disabled-user ShareMe stays disabled and receives no re-enable
command in the restoration scripts.

Post-reboot verification checks the disabled state as well as package presence,
and the execution summary lists disabled packages separately. Existing completed
groups are still skipped during resume; this change does not retroactively
rewrite the original cleanup artifacts or rerun C2 on the phone.

Validation: `ruby tests/workflow_test.rb` passed 12 tests with 74 assertions.
Coverage includes successful fallback/restoration commands, rejected disable,
misleading success output, launcher rollback to the prior explicit enabled
state, already-disabled preservation, and detection of unexpected re-enabling
by final verification. Shell syntax and `git diff --check` passed. This automated
integration was tested using simulated ADB; the physical eos was already
disabled during the separate user-authorized diagnostic test.
