#!/bin/sh
set -u

SERIAL="${1:?serial obrigatorio}"
ADB="${2:-./platform-tools/adb}"
OUT="${3:-results}"
MEASURES="$OUT/measurements.txt"
VERIFY="$OUT/final_verification.txt"
REMOVED="$OUT/removed.txt"

adb_cmd() { "$ADB" -s "$SERIAL" "$@" < /dev/null; }
now() { date '+%Y-%m-%d %H:%M:%S %Z'; }
present() { adb_cmd shell pm list packages --user 0 "$1" 2>/dev/null | tr -d '\r' | grep -qx "package:$1"; }

{
  printf '\n===== DEPOIS DO REINICIO E 2 MIN DE REPOUSO (%s) =====\n' "$(now)"
  adb_cmd shell cat /proc/meminfo 2>&1 | grep -E '^Mem(Total|Free|Available):'
  adb_cmd shell dumpsys diskstats 2>&1 | grep -E '^(Data-Free|App Cache Size):'
  adb_cmd shell df -h /data 2>&1 | tail -n 1
  printf 'Apps ativos user 0: '
  adb_cmd shell pm list packages -e --user 0 2>/dev/null | wc -l | tr -d ' '
  adb_cmd shell dumpsys battery 2>&1 | grep -E '^  (AC powered|USB powered|level|health|temperature):'
  adb_cmd shell dumpsys thermalservice 2>&1 | grep -m 1 'mName=battery' || true
  printf 'CPU em repouso (top 12):\n'
  adb_cmd shell dumpsys cpuinfo 2>&1 | sed -n '1,15p'
  printf 'Abertura de Configuracoes: nao repetida; am force-stop e incompativel/bloqueante nesta MIUI.\n'
} >> "$MEASURES"

: > "$VERIFY"
{
  printf 'VERIFICACAO FINAL (%s)\n' "$(now)"
  printf '\nBoot:\n'
  printf 'sys.boot_completed=%s\n' "$(adb_cmd shell getprop sys.boot_completed | tr -d '\r')"

  printf '\nUsuarios/perfis:\n'
  adb_cmd shell pm list users

  printf '\nPacotes aprovados para remocao (user 0):\n'
  sed '1,2d' "$REMOVED" | while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if present "$pkg"; then printf 'FALHA presente: %s\n' "$pkg"; else printf 'OK ausente: %s\n' "$pkg"; fi
  done

  printf '\nApps protegidos amostrados:\n'
  for pkg in com.chordbot com.dubox.drive com.google.android.apps.authenticator2 com.dts.freefireth com.brave.browser com.android.mms com.android.camera com.miui.gallery com.google.android.gms; do
    if present "$pkg"; then printf 'OK presente: %s\n' "$pkg"; else printf 'FALHA ausente: %s\n' "$pkg"; fi
  done

  printf '\nREQUEST_INSTALL_PACKAGES:\n'
  for pkg in com.android.chrome com.brave.browser com.google.android.apps.docs com.miui.gallery; do
    printf '%s: ' "$pkg"
    adb_cmd shell cmd appops get "$pkg" REQUEST_INSTALL_PACKAGES 2>&1 | tr '\n' ' '
    printf '\n'
  done

  printf '\nRede/privacidade:\n'
  printf 'wifi_scan_always_enabled=%s\n' "$(adb_cmd shell settings get global wifi_scan_always_enabled | tr -d '\r')"
  printf 'ble_scan_always_enabled=%s\n' "$(adb_cmd shell settings get global ble_scan_always_enabled | tr -d '\r')"
  printf 'private_dns_mode=%s\n' "$(adb_cmd shell settings get global private_dns_mode | tr -d '\r')"
  printf 'private_dns_specifier=%s\n' "$(adb_cmd shell settings get global private_dns_specifier | tr -d '\r')"
  if adb_cmd shell dumpsys connectivity 2>/dev/null | grep -q 'dns.adguard-dns.com'; then printf 'DNS AdGuard validado: sim\n'; else printf 'DNS AdGuard validado: nao\n'; fi
  if adb_cmd shell ping -c 1 dns.adguard-dns.com >/dev/null 2>&1; then printf 'Ping do hostname DNS: ok\n'; else printf 'Ping do hostname DNS: falhou\n'; fi

  printf '\nTela inicial:\n'
  adb_cmd shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
  sleep 1
  adb_cmd shell dumpsys window 2>/dev/null | grep -m 1 -E 'mCurrentFocus|mFocusedApp' || true

  printf '\nCompilacao:\n'
  printf 'speed-profile foi iniciado, mas a saida terminou em 13/370 sem marcador de sucesso; resultado nao comprovado.\n'
} >> "$VERIFY"

printf 'VERIFICACAO_OK\n'
