# Xiaomi endpoint log audit — 2026-11-12

Device: Xiaomi `22011119UY`, codename `eos`, Android 13 / MIUI 14 EEA.

## Findings

| Endpoint | Observed evidence | Attribution |
|---|---|---|
| `mcc.intl.inf.miui.com` | Eight failed HTTPS POST attempts to `/cloud/app/getData` | `com.xiaomi.joyose`, PID 15786, UID 1000 |
| `sdkconfig.ad.intl.xiaomi.com` | No matching hostname in captured or previously saved text logs | Not established |

The eight matching entries span device log times 12:09:34 to 13:54:33 on
2026-11-12. Each reports a failed connection to `0.0.0.0:443`, for example:

```text
11-12 13:54:33.397 15786 31992 E TEG_CONFIG: HttpUtil POST failed, url: https://mcc.intl.inf.miui.com/cloud/app/getData, error: Failed to connect to mcc.intl.inf.miui.com/0.0.0.0:443
```

PID attribution has two independent pieces of evidence:

```text
11-11 22:18:30.493 1591 1630 I ActivityManager: Start proc 15786:com.xiaomi.joyose/1000 for broadcast {com.xiaomi.joyose/com.xiaomi.joyose.JoyoseBroadCastReceiver} caller=android
```

The process snapshot also identifies PID 15786 as `com.xiaomi.joyose` with UID
1000. PackageManager reports the same package UID. UID 1000 is shared by system
components, so attribution is based on the specific PID/process and its start
record, not UID alone.

## Interpretation and limits

The logs establish attempted requests by Joyose, not successful transfers.
Connecting to `0.0.0.0` is consistent with name resolution being redirected or
blocked, but this capture does not establish which DNS/filtering mechanism
produced that address. The tag and path suggest a configuration request;
the log does not establish an advertising payload or what data was submitted.

No attribution can be made for `sdkconfig.ad.intl.xiaomi.com` from these logs.
Absence from logcat does not prove absence of traffic: apps need not log network
requests, buffers are finite, and the dump is not a packet capture. Other apps
may contact either endpoint without appearing in this material. No app was
launched, no traffic was deliberately generated, and no endpoint was contacted
by the diagnostic commands themselves.

Joyose was not added to the optional-removal list or altered by this audit.
Its system/game-service metadata and removal considerations are documented in
[the Joyose review](JOYOSE_REVIEW_2026-11-12.md). Subsequent changes made the three
store/community packages below part of the default cleanup; Joyose remains an
explicit selection only.
The requested optional apps were independently confirmed installed by exact
package ID: `com.xiaomi.glgm`, `com.xiaomi.mipicks`, `com.mi.global.bbs`. Their
presence does not establish that they contacted either endpoint.

## Method and local artifacts

Read-only ADB collection: `logcat -d -b all -v threadtime`, `ps -A -o
UID,PID,PPID,NAME`, and user-0 package lists with UIDs. Existing saved text logs
were searched too, including ignored `results/` files. No device logs were
cleared and no packages were removed in this investigation.

Local folder: `results/endpoint_audit_20261112/` (excluded from version control).

- `system_log.txt`: 228,608 lines from accessible logcat buffers.
- `endpoint_matches.txt`: eight matching domain records with source line numbers.
- `process_identity_evidence.txt`: Joyose process-start/application records.
- `processes.txt` and `matched_process.txt`: process snapshot and matching PID.
- `package_uids.txt`: package-to-UID mapping.
- `packages.txt`: installed package inventory.

The full system log can contain unrelated device/application metadata. Prefer
the filtered evidence and this report for sharing.
