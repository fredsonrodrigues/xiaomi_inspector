# Xiaomi Inspector — test on a second Xiaomi device

Date: 2026-11-06  
Timezone: Europe/Lisbon  
Status: **STOPPED AT THE FIRST ERROR**

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

