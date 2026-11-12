# Xiaomi Inspector

[Documentação em português](docs/README.pt-BR.md)

Xiaomi Inspector audits, plans, applies, and verifies a controlled cleanup of Xiaomi, Redmi, and POCO phones through ADB, without root.

The main entry point is [`xiaomi_inspector.sh`](./xiaomi_inspector.sh). It runs a read-only scan first, generates a package plan, requires explicit confirmation before changes, records hashes and actions, creates restoration scripts, and verifies the device after reboot.

> **Important:** ADB is not antivirus software. Xiaomi Inspector can identify indicators, settings, permissions, and attack surfaces, but it cannot prove that a device is malware-free.

## Safety boundaries

Xiaomi Inspector:

- always targets an explicit ADB serial;
- scans before allowing changes;
- restricts mutations to the primary Android user (`--user 0`);
- preserves Second Space/XSpace users;
- calculates SHA-256 hashes before removing packages;
- applies packages in small groups and checks the launcher after each group;
- attempts to restore the current group if validation fails;
- records measurements, changes, removed packages, and restoration commands;
- does not read messages, photos, contacts, passwords, tokens, or browser history;
- does not upload APKs, hashes, or the device package list to external services.

It does **not**:

- gain root access;
- unlock the bootloader;
- flash a ROM or firmware;
- perform a factory reset;
- delete personal files;
- disable Play Protect or system security features;
- update the Android security patch.

## Automatic device detection

All Xiaomi, Redmi, and POCO devices use the same workflow and current cleanup
profile. The program detects the manufacturer, model, and codename automatically;
`eos` and `platina` do not require separate commands. Manufacturer support is not
a guarantee that every firmware supports every operation: a failed stage stops
the workflow.

The profile retains the original approved groups A → F → B → D → C → E. Only
installed packages listed for removal in the generated plan are removed.
Missing apps are skipped, the default launcher is detected, and verification
compares the actual initial inventory with recorded removals. Review the plan
because the profile still encodes the owner's choices (including Google Photos,
CAIXA, My Vodafone, and Xiaomi cloud/sharing removal).

Each scan records the serial in `device_serial.txt`. Later stages reject results
from another phone. Use a new output folder for each complete run; a folder with
an existing cleanup log cannot be scanned again.

## Requirements

- macOS or Linux with a POSIX shell;
- a USB data cable;
- USB debugging enabled on the Android device;
- `curl` and `unzip` for the automatic Platform Tools installation;
- Ruby for generating the package plan;
- internet access on the first ADB operation and when the public UAD-NG list must be downloaded.

The Android SDK Platform Tools do not need to be bundled with the project. On the first command that requires ADB, Xiaomi Inspector:

1. detects macOS or Linux;
2. downloads the latest official Platform Tools archive from `dl.google.com`;
3. extracts it into `./platform-tools`;
4. validates that `platform-tools/adb` exists and is executable;
5. reuses that installation on later runs.

An explicitly configured custom `ADB` path is never downloaded or replaced automatically.

## Project layout

Before first use:

```text
.
├── xiaomi_inspector.sh
├── README.md
├── docs/
│   └── README.pt-BR.md
└── scripts/
    ├── scan_android.sh
    ├── build_plan.rb
    ├── apply_cleanup.sh
    └── verify_after.sh
```

After the first ADB command, `platform-tools/` is created automatically. Complete
runs create their own `results/run_DATE_TIME_PID/` folder. Individual stages use
`results/` unless `--out` or `OUT` selects another folder.

## Prepare the phone

1. Open **Settings → About phone**.
2. Tap **MIUI version** seven times to enable Developer options.
3. Open **Additional settings → Developer options**.
4. Enable **USB debugging**.
5. Connect the cable, unlock the phone, and accept **“Allow USB debugging?”**.

Check the connection:

```sh
./xiaomi_inspector.sh status
```

The first call may download Platform Tools. If multiple devices are connected, always provide the serial:

```sh
./xiaomi_inspector.sh scan --serial 63ea88ab
```

## Quick start

### Complete workflow

```sh
./xiaomi_inspector.sh
# Or choose a folder explicitly:
./xiaomi_inspector.sh --out results/my_phone_run
```

With no command, the program creates a new run folder under `results/` and runs:

```text
identify → scan → plan → approval → apply → reboot → idle period → verification → report
```

The workflow asks for confirmation before applying changes and rebooting.
For an already approved unattended run, use `--yes`:

```sh
./xiaomi_inspector.sh --out results/my_phone_run --yes
```

`run`, `all`, and `full` are aliases for this same complete workflow.
**Behavior change:** `all` now includes cleanup and reboot; use `scan` for a
read-only audit.

If a stage fails, resume the same phone and output folder with:

```sh
./xiaomi_inspector.sh --out results/my_phone_run --resume
```

Completed cleanup groups are skipped. If ShareMe (`com.xiaomi.midrop`) returns
`Failure [-1000]` on removal and remains installed, the workflow instead tries
`pm disable-user --user 0`. It checks the disabled-package list and the launcher,
records the package in `disabled.txt` (not `removed.txt`), and generates restoration
commands for its previous enabled state. An already disabled ShareMe is kept
disabled without generating a command that would re-enable it. If disabling or
verification fails, the group stops and attempts to restore its changes. Final
verification also checks that ShareMe remains disabled.

This fallback applies only to ShareMe and that specific uninstall response.
Other packages returning `Failure [-1000]` remain preserved in `skipped.txt`;
other removal errors interrupt the workflow. A resumed run skips groups already
completed before this change; start a new run to evaluate the updated profile.
If the first network-setting write is denied with `WRITE_SECURE_SETTINGS`, the
network group is recorded as pending and the workflow continues. Configure
Private DNS and Wi-Fi/BLE scanning manually on that phone; the summary includes
the pending task.

### Recommended staged workflow

```sh
./xiaomi_inspector.sh scan
./xiaomi_inspector.sh plan
./xiaomi_inspector.sh apply
./xiaomi_inspector.sh reboot-verify
./xiaomi_inspector.sh report
```

Running each stage separately lets you review `results/scan.txt` and `results/app_plan.tsv` before any changes.
To resume an automatic run, supply its printed folder with `--out` to every stage.

### Default Xiaomi apps and custom removals

These apps are included in the default cleanup. Missing packages are skipped:

| App | Exact package |
|---|---|
| Game Center / Centro de Jogos | `com.xiaomi.glgm` |
| Mi Picks / GetApps | `com.xiaomi.mipicks` |
| Xiaomi Community | `com.mi.global.bbs` |

```sh
./xiaomi_inspector.sh
```

To add any other installed app, repeat `--remove-app` with its full package ID.
There is no package allowlist. For example (replace the example IDs):

```sh
./xiaomi_inspector.sh --remove-app org.example.reader --remove-app com.example.other
```

This invokes the normal complete workflow, including its confirmations. Explicit
selections override keep/protect classifications in the plan, so review the
package, dependencies and local app data before confirming application. For a
read-only review, first run `scan --out results/review`, then:

```sh
./xiaomi_inspector.sh plan --out results/review --remove-app org.example.reader
```

Additional selections are stored in `optional_removals.txt`; only exact matches
in the inventory are marked for removal, including explicitly selected disabled
apps. No matching package means no removal. Package IDs must contain valid
letters/digits/underscores in dot-separated segments; wildcards, spaces and shell
expressions are rejected. Removal uses the existing logging, launcher validation, rollback,
restoration and final verification. Select options during `plan` or a new complete
run; `apply` and `--resume` use the saved plan without accepting new selections.

The latest endpoint-log investigation is documented in
[Endpoint audit — 2026-11-12](docs/network/ENDPOINT_AUDIT_2026-11-12.md).

Use a different output directory for an independent run:

```sh
./xiaomi_inspector.sh --out results/another_run
```

## Commands

### `status`

Lists connected ADB devices. It does not change the phone.

```sh
./xiaomi_inspector.sh status
```

### `scan`

Runs a read-only collection covering:

- build identity and verified boot state;
- Android security patch;
- Device Owner and device administrators;
- enabled, disabled, system, and third-party packages;
- installers, timestamps, permissions, and special access;
- accessibility, notification listeners, and overlays;
- proxy, VPN, Private DNS, and Wi-Fi/BLE scanning;
- battery, temperature, memory, CPU, and storage;
- camera packages and filtered camera warnings/errors.

```sh
./xiaomi_inspector.sh scan
```

Network output is sanitized so the report does not store SSIDs, BSSIDs, MAC addresses, or IP addresses.

### `plan`

Creates `results/app_plan.tsv`, classifying every active package as:

- `PROTEGER` — protect;
- `SUSPEITO` — requires investigation;
- `REMOVER (aguarda aprovacao)` — proposed removal, still awaiting approval;
- `MANTER NA DUVIDA` — keep when uncertain.

```sh
./xiaomi_inspector.sh plan
```

The program uses the complete public [Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation) list as a local reference. The device package list is not sent to UAD-NG.

A UAD-NG `Recommended` label never authorizes automatic removal by itself.

### `apply`

Applies only the fixed scope approved for this project. Before continuing, it requires the exact phrase:

```text
APLICAR NO USUARIO 0
```

```sh
./xiaomi_inspector.sh apply
```

Keep the phone connected, unlocked, and unused during this stage.

| Group | Action |
|---|---|
| A | Deny `REQUEST_INSTALL_PACKAGES` for Chrome, Brave, Google Drive, and MIUI Gallery |
| F | Trim app caches without deleting personal files or login data |
| B | Remove CAIXA, My Vodafone, WhatsWeb, Disable System Apps, and Google Photos from user 0 |
| D | Remove MIUI System Ads and Xiaomi Analytics from user 0 |
| C | Remove unused Mi Cloud, Xiaomi wallet, casting, and sharing components from user 0 |
| E | Disable persistent Wi-Fi/BLE scanning and configure `dns.adguard-dns.com` |

The workflow intentionally preserves ChordBot, the owner's apps, TeraBox, retained banking apps, games, 2FA, phone/SMS, camera/gallery, Google services, and Second Space/XSpace users.

The Settings launch benchmark is disabled because `am force-stop` blocked on this MIUI build. `speed-profile` compilation is also disabled by default because the original run did not produce a verifiable completion marker.

### `reboot-verify`

Requires the word `REINICIAR`, reboots the device, waits for `sys.boot_completed=1`, leaves it idle for two minutes, and verifies the result.

```sh
./xiaomi_inspector.sh reboot-verify
```

Afterward, manually test calls, SMS, keyboard, Wi-Fi, Bluetooth, camera, gallery, sharing, TeraBox, banking, 2FA, a game, and Second Space.

### `report`

Lists the generated artifacts and prints the automatic execution summary:

```sh
./xiaomi_inspector.sh report
```

### `restore`

Runs `results/restore.sh` after requiring the word `RESTAURAR`:

```sh
./xiaomi_inspector.sh restore
```

Restoration re-enables recorded packages and permissions, but it cannot guarantee recovery of local data belonging to third-party apps. Reboot and test the phone afterward.

## Options and environment variables

Supported options:

```text
--serial SERIAL
--out DIRECTORY
--yes             Confirm cleanup and reboot in an already approved run
--resume          Resume an existing run on the same device
--remove-app PACKAGE  Optional exact package selection; repeat for each app
```

Supported environment overrides:

```sh
ADB=/custom/path/to/adb
SERIAL=device_serial
OUT=/custom/results/path
```

Example:

```sh
SERIAL=63ea88ab OUT="$PWD/results_test" ./xiaomi_inspector.sh scan
```

## Generated files

Execution artifacts use English filenames in the selected output folder:

| File | Purpose |
|---|---|
| `device_serial.txt` | Binds the run to the scanned device |
| `device.txt` | Filtered device/build properties; do not publish without review |
| `scan.txt` | Raw, sanitized ADB scan |
| `before.txt` | Enabled packages before application |
| `uad_lists.json` | Local copy of the public UAD-NG package list |
| `app_plan.tsv` | Package classification and restoration guidance |
| `optional_removals.txt` | Exact optional package IDs selected when generating the plan |
| `measurements.txt` | Storage, memory, temperature, and package counts before/after |
| `changes.txt` | Commands, results, and SHA-256 hashes |
| `removed.txt` | Packages actually removed from user 0 |
| `disabled.txt` | Installed packages disabled by the ShareMe workaround |
| `skipped.txt` | Refused removals and pending configuration changes |
| `restore.sh` | Restoration commands for macOS/Linux |
| `restore.bat` | Restoration commands for Windows |
| `final_verification.txt` | Post-reboot verification |
| `execution_summary.txt` | Automatically generated run summary |
| `summary.txt` | Historical/manual consolidated report, when present |
| `approval_plan.txt` | Historical/manual approval plan, when present |

## Development checks

```sh
ruby tests/workflow_test.rb
sh -n xiaomi_inspector.sh
sh -n scripts/apply_cleanup.sh
sh -n scripts/verify_after.sh
ruby -c scripts/build_plan.rb
```

Tests use a simulated ADB executable and do not touch a connected phone.

## Privacy

Xiaomi Inspector is not intended to collect personal content. The scan records package names, permissions, configuration states, sizes, and counts.

Review `device.txt`, `changes.txt`, and the full scan before sharing them. They may contain technical details that identify the device configuration.

## Troubleshooting

### `unauthorized`

Unlock the phone and accept **“Allow USB debugging?”**. If the prompt does not appear, reconnect the cable while the screen is unlocked.

### No device appears

- try another data-capable cable;
- select USB **File transfer** mode;
- confirm USB debugging is still enabled;
- run `./platform-tools/adb kill-server` and retry.

### Multiple devices are connected

Use `--serial`:

```sh
./xiaomi_inspector.sh scan --serial SERIAL
```

### Automatic Platform Tools installation fails

Confirm that `curl`, `unzip`, DNS, and HTTPS access to `dl.google.com` work. If a partial `platform-tools/` directory exists without an executable `adb`, remove or repair that incomplete directory and retry.

### Device Owner is detected

The program stops before `apply`. A Device Owner can indicate corporate or school management. Do not bypass this protection without confirming ownership and policy.

### AdGuard DNS blocks a legitimate service

Use the generated restoration script or return to opportunistic Private DNS:

```sh
./platform-tools/adb -s SERIAL shell settings put global private_dns_mode opportunistic
./platform-tools/adb -s SERIAL shell settings delete global private_dns_specifier
```

### A MIUI update reinstalls packages

Run a new `scan`, compare the plan, and never reapply removals blindly.

## Known limitations

- ADB cannot prove the absence of malware or spyware.
- The Android security patch remains `2020-08-01`; app cleanup cannot patch Android, the kernel, modem, or Qualcomm drivers.
- Battery health percentage may not be available without manufacturer diagnostics.
- `dumpsys batterystats`, `diskstats`, and `cpuinfo` can contain stale or inconsistent sampling windows.
- Settings launch time is not measured on this MIUI build.
- Ads, tracking, stability, and battery life require observation over several days.
- Private browsing does not hide the IP address or prevent tracking through signed-in accounts, VPNs, proxies, certificates, or privileged apps.

## Syntax validation

```sh
sh -n xiaomi_inspector.sh
sh -n scripts/scan_android.sh
sh -n scripts/apply_cleanup.sh
sh -n scripts/verify_after.sh
ruby -c scripts/build_plan.rb
```

