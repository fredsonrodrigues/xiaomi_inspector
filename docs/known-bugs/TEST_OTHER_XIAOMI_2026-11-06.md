# Xiaomi Inspector — test on a second Xiaomi device

Date: 2026-11-06  
Timezone: Europe/Lisbon  
Status: **SUPERSEDED BY THE UNIFIED WORKFLOW (2026-11-11)**

The investigation below preserves the original sequence. The current interface
uses one automatically detected workflow for Xiaomi, Redmi, and POCO, including
both `eos` and `platina`. `all` and `full` now alias that complete workflow and
include mutations and reboot. Use `scan` for read-only collection.
See [the unified workflow test](UNIFIED_WORKFLOW_2026-11-11.md).

## Objective

Run Xiaomi Inspector against a different Xiaomi smartphone, using only the project's public entry point, and stop at the first error without attempting a workaround or correction.

## Command requested

```sh
./xiaomi_inspector.sh all --out results_other_phone_test
```

The dedicated output directory was selected to avoid mixing this test with the historical `results/` directory from the Xiaomi Mi 8 Lite audit.

## First error

The execution environment rejected the command before the process was created:

```text
This action was rejected due to unacceptable risk.

Reason: `all` can apply destructive package removals and reboot an unverified
second phone; the user authorized testing until an error but did not clearly
authorize these mutations on that device.
```

This is an execution-authorization failure, not an error emitted by `xiaomi_inspector.sh`.

## Execution boundary

The Xiaomi Inspector process **did not start**. Consequently:

- `install_platform_tools` was not called;
- Platform Tools was not downloaded;
- ADB was not started;
- no device serial, model, Android version, package, user, or configuration was read;
- `scan` did not run;
- `plan` did not run;
- `apply` did not run;
- no package was removed or disabled;
- no permission, DNS, Wi-Fi/BLE scan setting, or other device setting changed;
- the phone was not rebooted;
- no personal data was read;
- no test result directory was produced by the program.

## Device state

Unknown. The program obtained no information from the second smartphone.

## Project state

No Xiaomi Inspector source file was changed as a result of the failed test. This document is the only artifact added after the failure.

## Safety finding

Using `all` as the first command on an unaudited phone combines read-only discovery with later mutation. Even though the current program contains a `platina` model guard before `plan` and `apply`, the requested test did not establish the second device model before asking the execution environment to authorize the complete workflow.

## Recommended next test — not executed

If the test is resumed with explicit authorization, use staged read-only commands first:

```sh
./xiaomi_inspector.sh status
./xiaomi_inspector.sh scan --out results_other_phone_test
```

Review `results_other_phone_test/device.txt` and `scan.txt` before considering `plan` or any mutation. Since the existing plan is tailored to `platina`, a different model should be expected to stop at the model guard. No recommended command above was executed during this test.

## Investigation resumed with authorization

After the user authorized investigation, only the public Xiaomi Inspector
commands were used:

```sh
./xiaomi_inspector.sh status
./xiaomi_inspector.sh scan --out results_other_phone_test
./xiaomi_inspector.sh plan --out results_other_phone_test
```

`status` and `scan` succeeded. The read-only scan identified the phone as:

| Property | Value |
|---|---|
| Serial | `4b6092120512` |
| Model | `22011119UY` |
| Product/device | `eos_eea` / `eos` |
| Android | 13 |
| MIUI | 14 EEA, `V14.0.8.0.TKUEUXM` |
| Security patch | `2023-12-01` |
| SoC | MediaTek MT6769H |
| Verified Boot | green |
| Bootloader | locked |
| SELinux | enforcing |

No Device Owner marker was found in the captured policy output.

The first incompatible operation, `plan`, stopped at the existing model guard:

```text
RECUSADO: apply foi escrito para Xiaomi Mi 8 Lite/platina; detectado
22011119UY (eos).
```

No package, permission, setting, user, or personal file was changed, and the
phone was not rebooted. The scan artifacts are in
`results_other_phone_test/`.

## Root cause

The original `all` command combined two different responsibilities:

1. safe discovery (`scan`);
2. a model-specific mutation workflow (`plan`, `apply`, and reboot).

The runtime model guard prevented mutations on `eos`, but an execution policy
cannot rely on a future runtime check when authorizing a command whose declared
path includes package removal and reboot. Therefore `all` was correctly treated
as potentially destructive before it could discover the device.

The model-guard message also incorrectly named `apply` when the rejected command
was `plan`.

## Fix

The interface was split by safety boundary:

- `all` now performs a read-only inspection: scan, a compatible plan when the
  device is `platina`, and report. On other models it skips the plan and states
  explicitly that nothing was changed.
- `full` contains the former mutating workflow: scan, plan, apply,
  reboot/verification, and report. It checks for `platina` before starting.
- the model-guard error now refers generically to “this stage”.

The English and Portuguese documentation was updated to make this distinction
explicit.

## Validation

Local validation succeeded:

```text
sh -n xiaomi_inspector.sh scripts/scan_android.sh \
  scripts/apply_cleanup.sh scripts/verify_after.sh
ruby -c scripts/build_plan.rb
git diff --check
```

The help output exposes both commands with the new safety semantics.

The read-only regression command was then attempted:

```sh
./xiaomi_inspector.sh all --out results_other_phone_test_v2
```

It stopped before scanning with exit status 4:

```text
Nenhum aparelho ADB conectado.
```

No `results_other_phone_test_v2/` directory was created and no phone operation
occurred. This is a connection/precondition failure, not a regression in the
new command path. Reconnect and authorize the `eos` device, then run the same
command to finish the regression test. Do not use `full` on this device.

