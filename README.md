# Xiaomi Inspector

[Documentação em português](docs/README.pt-BR.md)

Xiaomi Inspector is a shell-based workflow for auditing, planning, applying, and verifying a controlled cleanup of a **Xiaomi Phone(`platina`)** through ADB, without root.

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

## Device-specific limitation

The read-only scan can inspect other Android devices. However, `plan`, `apply`, `reboot-verify`, and `restore` are tailored to the device and decisions documented in this project:

- Xiaomi Mi 8 Lite;
- device codename `platina`;
- Android 10 / MIUI 12 Global;
- primary user 0;
- Second Space/XSpace users 11 and 999;
- the approved package selection from the original audit.

Before applying changes, the program checks `ro.product.device` and **refuses any device other than `platina`**. Do not reuse this removal list on another phone without a new audit.

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

After the first ADB command, `platform-tools/` is created automatically. Execution artifacts are stored in `results/` by default.

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

### Full workflow

```sh
./xiaomi_inspector.sh all
```

The default output directory is `./results`.

The workflow is:

```text
scan → review → plan → approval → apply → reboot → idle period → verification
```

Even in `all` mode, Xiaomi Inspector stops for explicit confirmation before applying changes and before rebooting.

### Recommended staged workflow

```sh
./xiaomi_inspector.sh scan
./xiaomi_inspector.sh plan
./xiaomi_inspector.sh apply
./xiaomi_inspector.sh reboot-verify
./xiaomi_inspector.sh report
```

Running each stage separately lets you review `results/scan.txt` and `results/app_plan.tsv` before any changes.

Use a different output directory for an independent run:

```sh
./xiaomi_inspector.sh all --out results_20261106
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

All execution artifacts are written to `results/` by default, using English filenames:

| File | Purpose |
|---|---|
| `device.txt` | Filtered device/build properties; do not publish without review |
| `scan.txt` | Raw, sanitized ADB scan |
| `before.txt` | Enabled packages before application |
| `uad_lists.json` | Local copy of the public UAD-NG package list |
| `app_plan.tsv` | Package classification and restoration guidance |
| `measurements.txt` | Storage, memory, temperature, and package counts before/after |
| `changes.txt` | Commands, results, and SHA-256 hashes |
| `removed.txt` | Packages actually removed from user 0 |
| `restore.sh` | Restoration commands for macOS/Linux |
| `restore.bat` | Restoration commands for Windows |
| `final_verification.txt` | Post-reboot verification |
| `execution_summary.txt` | Automatically generated run summary |
| `summary.txt` | Historical/manual consolidated report, when present |
| `approval_plan.txt` | Historical/manual approval plan, when present |

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

