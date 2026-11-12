#!/bin/sh
set -eu

SERIAL="${1:?serial obrigatorio}"
ADB="${2:-./platform-tools/adb}"
OUT="${3:-results}"
MODE="${4:-full}"
CHANGES="$OUT/changes.txt"
REMOVED="$OUT/removed.txt"
MEASURES="$OUT/measurements.txt"
RESTORE_BAT="$OUT/restore.bat"
RESTORE_SH="$OUT/restore.sh"
HOME_COMPONENT=$("$ADB" -s "$SERIAL" shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r' | tail -n 1)
HOME_PACKAGE=${HOME_COMPONENT%%/*}
case "$HOME_COMPONENT" in */*) ;; *) printf 'Launcher padrao nao identificado.\n' >&2; exit 9 ;; esac

adb_cmd() { "$ADB" -s "$SERIAL" "$@" < /dev/null; }
now() { date '+%Y-%m-%d %H:%M:%S %Z'; }
log() { printf '[%s] %s\n' "$(now)" "$*" >> "$CHANGES"; }

exact_package_present() {
  adb_cmd shell pm list packages --user 0 "$1" 2>/dev/null | tr -d '\r' | grep -qx "package:$1"
}

home_ok() {
  adb_cmd shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
  sleep 1
  focus="$(adb_cmd shell dumpsys window 2>/dev/null | grep -m 1 -E 'mCurrentFocus|mFocusedApp' || true)"
  log "Foco apos grupo: $focus"
  printf '%s' "$focus" | grep -Fq "$HOME_PACKAGE/"
}

record_restore_appops() {
  pkg="$1"
  mode="$2"
  printf '"%%ADB%%" -s %%SERIAL%% shell cmd appops set --user 0 %s REQUEST_INSTALL_PACKAGES %s\n' "$pkg" "$mode" >> "$RESTORE_BAT"
  printf '"$ADB" -s "$SERIAL" shell cmd appops set --user 0 %s REQUEST_INSTALL_PACKAGES %s\n' "$pkg" "$mode" >> "$RESTORE_SH"
}

record_restore_package() {
  pkg="$1"
  printf '"%%ADB%%" -s %%SERIAL%% shell cmd package install-existing --user 0 %s\n' "$pkg" >> "$RESTORE_BAT"
  printf '"$ADB" -s "$SERIAL" shell cmd package install-existing --user 0 %s\n' "$pkg" >> "$RESTORE_SH"
}

measure_snapshot() {
  label="$1"
  {
    printf '\n===== %s (%s) =====\n' "$label" "$(now)"
    adb_cmd shell cat /proc/meminfo 2>&1 | grep -E '^Mem(Total|Free|Available):'
    adb_cmd shell dumpsys diskstats 2>&1 | grep -E '^(Data-Free|App Cache Size):'
    adb_cmd shell df -h /data 2>&1 | tail -n 1
    printf 'Apps ativos user 0: '
    adb_cmd shell pm list packages -e --user 0 2>/dev/null | wc -l | tr -d ' '
    adb_cmd shell dumpsys battery 2>&1 | grep -E '^  (AC powered|USB powered|level|health|temperature):'
    adb_cmd shell dumpsys thermalservice 2>&1 | grep -m 1 'mName=battery' || true
    printf 'Abertura de Configuracoes:\n'
  } >> "$MEASURES"
  if [ "${ENABLE_SETTINGS_BENCH:-0}" = 1 ]; then
    i=1
    while [ "$i" -le 3 ]; do
      adb_cmd shell am force-stop com.android.settings >/dev/null 2>&1 || true
      adb_cmd shell am start -W -n com.android.settings/.Settings 2>&1 | grep -E '^(Status|TotalTime|WaitTime|Complete)' >> "$MEASURES" || printf 'Tentativa %s: indisponivel\n' "$i" >> "$MEASURES"
      i=$((i + 1))
    done
  else
    printf 'Omitida por padrao: am force-stop foi bloqueante na MIUI 12 deste aparelho.\n' >> "$MEASURES"
  fi
  adb_cmd shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
}

rollback_appops() {
  for entry in "$@"; do
    pkg=${entry%:*}
    mode=${entry##*:}
    adb_cmd shell cmd appops set --user 0 "$pkg" REQUEST_INSTALL_PACKAGES "$mode" >/dev/null 2>&1 || true
    log "ROLLBACK appops $mode: $pkg"
  done
}

apply_group_a() {
  changed=""
  for pkg in com.android.chrome com.brave.browser com.google.android.apps.docs com.miui.gallery; do
    if ! exact_package_present "$pkg"; then log "A ignorado (ausente): $pkg"; continue; fi
    before="$(adb_cmd shell cmd appops get --user 0 "$pkg" REQUEST_INSTALL_PACKAGES 2>&1 | tr '\n' ' ')"
    old_appop=$(printf '%s' "$before" | sed -n 's/.*REQUEST_INSTALL_PACKAGES: \([a-z]*\).*/\1/p')
    old_appop=${old_appop:-default}
    case "$old_appop" in allow|deny|ignore|default|foreground) ;; *) log "Modo appops desconhecido: $before"; return 1 ;; esac
    log "A antes $pkg: $before"
    if printf '%s' "$before" | grep -q 'deny'; then
      log "A ja aplicado anteriormente: $pkg"
      continue
    fi
    if ! adb_cmd shell cmd appops set --user 0 "$pkg" REQUEST_INSTALL_PACKAGES deny >> "$CHANGES" 2>&1; then
      rollback_appops $changed
      log "FALHA grupo A em $pkg"
      return 1
    fi
    after="$(adb_cmd shell cmd appops get --user 0 "$pkg" REQUEST_INSTALL_PACKAGES 2>&1 | tr '\n' ' ')"
    if ! printf '%s' "$after" | grep -q 'deny'; then
      rollback_appops $changed "$pkg:$old_appop"
      log "FALHA verificacao grupo A em $pkg: $after"
      return 1
    fi
    changed="$changed $pkg:$old_appop"
    log "A aplicado $pkg: $after"
  done
  if ! home_ok; then
    rollback_appops $changed
    log "FALHA tela inicial grupo A; restaurado"
    return 1
  fi
  for entry in $changed; do record_restore_appops "${entry%:*}" "${entry##*:}"; done
  log "GRUPO A CONCLUIDO"
}

hash_package() {
  pkg="$1"
  log "SHA-256 antes de remover $pkg"
  paths="$(adb_cmd shell pm path --user 0 "$pkg" 2>/dev/null | sed 's/^package://' | tr -d '\r')"
  if [ -z "$paths" ]; then
    log "SHA-256 indisponivel: nenhum APK localizado para $pkg"
    return 0
  fi
  for apk in $paths; do
    adb_cmd shell sha256sum "$apk" >> "$CHANGES" 2>&1 || log "SHA-256 indisponivel para $apk"
  done
}

rollback_packages() {
  for pkg in "$@"; do
    result="$(adb_cmd shell cmd package install-existing --user 0 "$pkg" 2>&1 || true)"
    log "ROLLBACK pacote $pkg: $result"
  done
}

rollback_disabled() {
  for disable_entry in "$@"; do
    disable_pkg=${disable_entry%:*}
    disable_restore=${disable_entry##*:}
    adb_cmd shell pm "$disable_restore" --user 0 "$disable_pkg" >> "$CHANGES" 2>&1 || {
      log "FALHA rollback de desativacao: $disable_pkg"; return 1
    }
  done
}

disable_shareme() {
  # Specific fallback observed and tested on MIUI; do not disable other apps.
  fallback_state=$(adb_cmd shell dumpsys package com.xiaomi.midrop | tr -d '\r' | sed -n 's/.*User 0:.* enabled=\([0-9]*\).*/\1/p')
  case "$fallback_state" in
    0) fallback_restore=default-state ;;
    1) fallback_restore=enable ;;
    2) fallback_restore=disable ;;
    3) fallback_restore=disable-user ;;
    4) fallback_restore=disable-until-used ;;
    *) log "FALHA workaround ShareMe: estado anterior desconhecido"; return 1 ;;
  esac
  if [ "$fallback_state" = 3 ]; then
    log "ShareMe ja estava disabled-user; estado preservado"
    return 0
  fi
  if ! adb_cmd shell pm disable-user --user 0 com.xiaomi.midrop >> "$CHANGES" 2>&1; then
    rollback_disabled "com.xiaomi.midrop:$fallback_restore" || true
    log "FALHA workaround ShareMe: disable-user recusado"
    return 1
  fi
  if ! adb_cmd shell pm list packages -d --user 0 com.xiaomi.midrop | tr -d '\r' | grep -qx 'package:com.xiaomi.midrop'; then
    rollback_disabled "com.xiaomi.midrop:$fallback_restore" || true
    log "FALHA workaround ShareMe: desativacao nao confirmada"
    return 1
  fi
  log "WORKAROUND ShareMe: desativado no user 0; estado anterior=$fallback_state"
}

remove_group() {
  group="$1"
  shift
  changed=""
  disabled_changed=""
  shareme_disabled=no
  for pkg in "$@"; do
    if ! exact_package_present "$pkg"; then
      log "Grupo $group: $pkg ja ausente no user 0; nao registrado como removido"
      continue
    fi
    if ! awk -F '\t' -v pkg="$pkg" '$1 == pkg && $5 == "REMOVER (aguarda aprovacao)" {found=1} END {exit !found}' "$OUT/app_plan.tsv"; then
      log "Grupo $group: $pkg preservado pelo plano"
      continue
    fi
    hash_package "$pkg"
    result="$(adb_cmd shell pm uninstall --user 0 "$pkg" 2>&1 || true)"
    log "Grupo $group uninstall $pkg: $result"
    if [ "$result" = 'Failure [-1000]' ] && exact_package_present "$pkg"; then
      if [ "$pkg" = com.xiaomi.midrop ]; then
        if ! disable_shareme; then
          rollback_packages $changed
          rollback_disabled $disabled_changed || true
          return 1
        fi
        shareme_disabled=yes
        if [ "$fallback_state" != 3 ]; then
          disabled_changed="$disabled_changed com.xiaomi.midrop:$fallback_restore"
        fi
        continue
      fi
      printf '%s\t%s\t%s\n' "$group" "$pkg" "$result" >> "$OUT/skipped.txt"
      log "Grupo $group: remocao recusada (-1000); $pkg preservado"
      continue
    fi
    if [ "$result" != "Success" ] || exact_package_present "$pkg"; then
      rollback_packages $changed
      rollback_disabled $disabled_changed || true
      log "FALHA grupo $group em $pkg; grupo restaurado"
      return 1
    fi
    changed="$changed $pkg"
  done
  if ! home_ok; then
    rollback_packages $changed
    rollback_disabled $disabled_changed || true
    log "FALHA tela inicial grupo $group; grupo restaurado"
    return 1
  fi
  for pkg in $changed; do
    printf '%s\n' "$pkg" >> "$REMOVED"
    record_restore_package "$pkg"
  done
  if [ "$shareme_disabled" = yes ]; then
    if ! grep -Fxq com.xiaomi.midrop "$OUT/disabled.txt" 2>/dev/null; then
      printf 'com.xiaomi.midrop\n' >> "$OUT/disabled.txt"
    fi
    for disable_entry in $disabled_changed; do
      disable_pkg=${disable_entry%:*}
      disable_restore=${disable_entry##*:}
      printf '"$ADB" -s "$SERIAL" shell pm %s --user 0 %s\n' "$disable_restore" "$disable_pkg" >> "$RESTORE_SH"
      printf '"%%ADB%%" -s %%SERIAL%% shell pm %s --user 0 %s\n' "$disable_restore" "$disable_pkg" >> "$RESTORE_BAT"
    done
  fi
  log "GRUPO $group CONCLUIDO:$changed"
}

apply_trim() {
  before="$(adb_cmd shell dumpsys diskstats 2>&1 | grep '^Data-Free:' || true)"
  log "F antes trim: $before"
  result="$(adb_cmd shell pm trim-caches 999G 2>&1 || true)"
  log "F pm trim-caches: ${result:-sem saida}"
  after="$(adb_cmd shell dumpsys diskstats 2>&1 | grep '^Data-Free:' || true)"
  log "F depois trim: $after"
  {
    printf '\n===== APOS TRIM-CACHES (%s) =====\n' "$(now)"
    printf 'Antes: %s\nDepois: %s\n' "$before" "$after"
    adb_cmd shell df -h /data 2>&1 | tail -n 1
  } >> "$MEASURES"
  home_ok || { log "AVISO: tela inicial nao confirmada apos F"; return 1; }
  log "GRUPO F CONCLUIDO"
}

restore_network() {
  adb_cmd shell settings put global wifi_scan_always_enabled "${old_wifi:-1}" >/dev/null 2>&1 || true
  adb_cmd shell settings put global ble_scan_always_enabled "${old_ble:-1}" >/dev/null 2>&1 || true
  adb_cmd shell settings put global private_dns_mode "${old_mode:-opportunistic}" >/dev/null 2>&1 || true
  if [ "${old_spec:-null}" = null ] || [ -z "${old_spec:-}" ]; then
    adb_cmd shell settings delete global private_dns_specifier >/dev/null 2>&1 || true
  else
    adb_cmd shell settings put global private_dns_specifier "$old_spec" >/dev/null 2>&1 || true
  fi
  log "ROLLBACK grupo E para wifi=${old_wifi:-1} ble=${old_ble:-1} mode=${old_mode:-opportunistic} spec=${old_spec:-null}"
}

apply_group_e() {
  old_wifi="$(adb_cmd shell settings get global wifi_scan_always_enabled | tr -d '\r')"
  old_ble="$(adb_cmd shell settings get global ble_scan_always_enabled | tr -d '\r')"
  old_mode="$(adb_cmd shell settings get global private_dns_mode | tr -d '\r')"
  old_spec="$(adb_cmd shell settings get global private_dns_specifier | tr -d '\r')"
  network_changed=yes
  if [ "$old_wifi" = 0 ] && [ "$old_ble" = 0 ] && [ "$old_mode" = hostname ] && [ "$old_spec" = dns.adguard-dns.com ]; then
    network_changed=no
  fi
  log "E antes: wifi=$old_wifi ble=$old_ble mode=$old_mode spec=$old_spec"
  if first_write=$(adb_cmd shell settings put global wifi_scan_always_enabled 0 2>&1); then
    printf '%s\n' "$first_write" >> "$CHANGES"
  else
    printf '%s\n' "$first_write" >> "$CHANGES"
    if printf '%s' "$first_write" | grep -q 'Permission denial.*WRITE_SECURE_SETTINGS'; then
      printf 'E\tglobal_settings\tWRITE_SECURE_SETTINGS denied; configure DNS/Wi-Fi/BLE manually\n' >> "$OUT/skipped.txt"
      log "GRUPO E PENDENTE: firmware recusou WRITE_SECURE_SETTINGS antes de qualquer mudanca de rede"
      printf 'Grupo E pendente: ADB sem permissao para configurar DNS/Wi-Fi/BLE. Consulte skipped.txt.\n'
      return 0
    fi
    restore_network
    return 1
  fi
  adb_cmd shell settings put global ble_scan_always_enabled 0 >> "$CHANGES" 2>&1 || { restore_network; return 1; }
  adb_cmd shell settings put global private_dns_specifier dns.adguard-dns.com >> "$CHANGES" 2>&1 || { restore_network; return 1; }
  adb_cmd shell settings put global private_dns_mode hostname >> "$CHANGES" 2>&1 || { restore_network; return 1; }
  sleep 4
  wifi="$(adb_cmd shell settings get global wifi_scan_always_enabled | tr -d '\r')"
  ble="$(adb_cmd shell settings get global ble_scan_always_enabled | tr -d '\r')"
  mode="$(adb_cmd shell settings get global private_dns_mode | tr -d '\r')"
  spec="$(adb_cmd shell settings get global private_dns_specifier | tr -d '\r')"
  dns_ok=no
  adb_cmd shell dumpsys connectivity 2>/dev/null | grep -q 'dns.adguard-dns.com' && dns_ok=yes
  ping_ok=no
  adb_cmd shell ping -c 1 dns.adguard-dns.com >/dev/null 2>&1 && ping_ok=yes
  log "E depois: wifi=$wifi ble=$ble mode=$mode spec=$spec dns_validado=$dns_ok ping=$ping_ok"
  if [ "$wifi" != 0 ] || [ "$ble" != 0 ] || [ "$mode" != hostname ] || [ "$spec" != dns.adguard-dns.com ] || [ "$dns_ok" != yes ] || [ "$ping_ok" != yes ]; then
    restore_network
    log "FALHA validacao grupo E; restaurado"
    return 1
  fi
  if ! home_ok; then restore_network; log "FALHA tela inicial grupo E; restaurado"; return 1; fi
  if [ "$network_changed" = yes ]; then
    printf '"%%ADB%%" -s %%SERIAL%% shell settings put global wifi_scan_always_enabled %s\n' "$old_wifi" >> "$RESTORE_BAT"
    printf '"%%ADB%%" -s %%SERIAL%% shell settings put global ble_scan_always_enabled %s\n' "$old_ble" >> "$RESTORE_BAT"
    printf '"%%ADB%%" -s %%SERIAL%% shell settings put global private_dns_mode %s\n' "$old_mode" >> "$RESTORE_BAT"
    if [ "$old_spec" = null ] || [ -z "$old_spec" ]; then
      printf '"%%ADB%%" -s %%SERIAL%% shell settings delete global private_dns_specifier\n' >> "$RESTORE_BAT"
    else
      printf '"%%ADB%%" -s %%SERIAL%% shell settings put global private_dns_specifier %s\n' "$old_spec" >> "$RESTORE_BAT"
    fi
    printf '"$ADB" -s "$SERIAL" shell settings put global wifi_scan_always_enabled %s\n' "$old_wifi" >> "$RESTORE_SH"
    printf '"$ADB" -s "$SERIAL" shell settings put global ble_scan_always_enabled %s\n' "$old_ble" >> "$RESTORE_SH"
    printf '"$ADB" -s "$SERIAL" shell settings put global private_dns_mode %s\n' "$old_mode" >> "$RESTORE_SH"
    if [ "$old_spec" = null ] || [ -z "$old_spec" ]; then
      printf '"$ADB" -s "$SERIAL" shell settings delete global private_dns_specifier\n' >> "$RESTORE_SH"
    else
      printf '"$ADB" -s "$SERIAL" shell settings put global private_dns_specifier %s\n' "$old_spec" >> "$RESTORE_SH"
    fi
  fi
  log "GRUPO E CONCLUIDO"
}

log "INICIO DA APLICACAO APROVADA"
if [ "$MODE" = "resume" ]; then
  log "RETOMADA: medidas iniciais ja coletadas; teste am force-stop indisponivel nesta MIUI"
else
  measure_snapshot "ANTES"
fi
run_stage() {
  stage=$1
  shift
  if [ "$MODE" = resume ] && grep -q "GRUPO $stage CONCLUIDO" "$CHANGES"; then
    log "RETOMADA: grupo $stage ja concluido"
    return 0
  fi
  "$@"
}
run_stage A apply_group_a || exit 10
run_stage F apply_trim || exit 20
run_stage B remove_group B br.com.gabba.Caixa com.vodafone.mCare com.geeksoftapps.whatsweb com.learnpainless.disable_system_apps com.google.android.apps.photos || exit 30
run_stage D remove_group D com.miui.msa.global com.miui.analytics || exit 40
run_stage C1 remove_group C1 com.miui.cloudbackup com.miui.micloudsync com.miui.cloudservice com.miui.cloudservice.sysbase com.xiaomi.payment com.mipay.wallet.id || exit 50
run_stage C2 remove_group C2 com.xiaomi.midrop com.miui.mishare.connectivity com.xiaomi.mi_connect_service com.xiaomi.miplay_client com.milink.service || exit 60
run_stage X remove_group X com.xiaomi.glgm com.xiaomi.mipicks com.mi.global.bbs || exit 65
if [ -s "$OUT/optional_removals.txt" ]; then
  set --
  while IFS= read -r requested_pkg || [ -n "$requested_pkg" ]; do
    [ -n "$requested_pkg" ] || continue
    if ! printf '%s\n' "$requested_pkg" | LC_ALL=C grep -Eq '^([A-Za-z][A-Za-z0-9_]*\.)*[A-Za-z][A-Za-z0-9_]*$'; then
      log "FALHA nome de pacote invalido na selecao: $requested_pkg"; exit 65
    fi
    set -- "$@" "$requested_pkg"
  done < "$OUT/optional_removals.txt"
  run_stage OPTIONAL remove_group OPTIONAL "$@" || exit 65
fi
run_stage E apply_group_e || exit 70

avail_kb="$(adb_cmd shell df -k /data 2>/dev/null | tail -n 1 | awk '{print $4}')"
charging="$(adb_cmd shell dumpsys battery 2>/dev/null | grep -E '^  (AC|USB) powered: true' | wc -l | tr -d ' ')"
if [ "${ENABLE_COMPILE:-0}" = 1 ] && [ "${avail_kb:-0}" -ge 4194304 ] && [ "${charging:-0}" -ge 1 ]; then
  result="$(adb_cmd shell cmd package compile -m speed-profile -a 2>&1 || true)"
  log "Compilacao speed-profile: $result"
else
  log "Compilacao omitida por padrao ou pre-condicao: enable=${ENABLE_COMPILE:-0} livre=${avail_kb:-indisponivel}KB charging=${charging:-0}"
fi

log "APLICACAO CONCLUIDA; REINICIO PENDENTE"
printf 'APLICACAO_OK\n'
