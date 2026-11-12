#!/bin/sh
set -u

SERIAL="${1:?serial ADB obrigatorio}"
ADB="${2:-./platform-tools/adb}"
OUT="${3:-results}"
SCAN="$OUT/scan.txt"
DEVICE="$OUT/device.txt"
BEFORE="$OUT/before.txt"
TMP="$OUT/.scan_tmp"

mkdir -p "$OUT" "$TMP"
: > "$SCAN"
: > "$DEVICE"
: > "$BEFORE"

adb_cmd() {
  "$ADB" -s "$SERIAL" "$@" < /dev/null
}

section() {
  printf '\n===== %s =====\n' "$1" >> "$SCAN"
}

run_shell() {
  title="$1"
  shift
  section "$title"
  adb_cmd shell "$@" >> "$SCAN" 2>&1 || printf '[COMANDO INDISPONIVEL OU FALHOU]\n' >> "$SCAN"
}

printf 'Relatorio bruto de varredura ADB (somente leitura)\n' >> "$SCAN"
printf 'Serial: %s\n' "$SERIAL" >> "$SCAN"
printf 'Coletado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" >> "$SCAN"

# Identidade filtrada; este arquivo nao deve ser publicado.
adb_cmd shell getprop > "$TMP/getprop.txt" 2>&1 || {
  printf 'Falha ao ler identidade do aparelho.\n' >&2; exit 4
}
grep -E '^\[(ro\.product\.(model|manufacturer|device|first_api_level)|ro\.(build|system\.build)\.(version\.release|display\.id|version\.security_patch|tags|type|fingerprint)|ro\.vendor\.build\.security_patch|ro\.(soc\.model|board\.platform|secure|debuggable|adb\.secure)|ro\.boot\.(verifiedbootstate|flash\.locked|warranty_bit|vbmeta\.device_state|veritymode)|ro\.miui\.|ro\.product\.mod_device)' "$TMP/getprop.txt" > "$DEVICE" || true

section "IDENTIDADE E INTEGRIDADE (getprop filtrado)"
cp "$DEVICE" "$TMP/device_copy.txt"
sed -E 's/\[([^]]+)\]: \[([^]]*)\]/\1=\2/' "$TMP/device_copy.txt" >> "$SCAN"
run_shell "USUARIOS" pm list users
run_shell "DEVICE POLICY" dumpsys device_policy

section "APPS ATIVOS -- USER 0"
adb_cmd shell pm list packages -e --user 0 > "$BEFORE" 2>&1 || {
  printf 'Falha ao coletar inventario; plano/aplicacao interrompidos.\n' >&2; exit 4
}
grep -q '^package:android' "$BEFORE" || {
  printf 'Inventario vazio ou invalido; plano/aplicacao interrompidos.\n' >&2; exit 4
}
cat "$BEFORE" >> "$SCAN"
run_shell "APPS DESATIVADOS -- USER 0" pm list packages -d --user 0
run_shell "APPS DE SISTEMA -- USER 0" pm list packages -s --user 0
run_shell "APPS DE TERCEIROS -- USER 0" pm list packages -3 --user 0
run_shell "INSTALADORES DOS APPS DE TERCEIROS" pm list packages -i -3 --user 0
run_shell "PACOTES E UIDS -- USER 0" pm list packages -U --user 0

adb_cmd shell pm list packages -3 --user 0 | sed 's/^package://' | tr -d '\r' > "$TMP/third_party.txt"
section "DETALHES FILTRADOS DOS APPS DE TERCEIROS"
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  printf '\n--- %s ---\n' "$pkg" >> "$SCAN"
  adb_cmd shell dumpsys package "$pkg" 2>&1 | grep -E 'firstInstallTime=|lastUpdateTime=|installerPackageName=|initiatingPackageName=|versionName=|granted=true|grantedPermissions:|android.permission\.' >> "$SCAN" || printf '[SEM DETALHES OU INDISPONIVEL]\n' >> "$SCAN"
done < "$TMP/third_party.txt"

run_shell "ACESSIBILIDADE ATIVA" settings get secure enabled_accessibility_services
run_shell "LEITORES DE NOTIFICACOES" settings get secure enabled_notification_listeners
run_shell "APPOPS SOBREPOSICAO PERMITIDA" appops query-op SYSTEM_ALERT_WINDOW allow
run_shell "APPOPS INSTALAR PACOTES PERMITIDA" appops query-op REQUEST_INSTALL_PACKAGES allow
for pkg in com.miui.gallery com.android.chrome com.google.android.apps.docs com.brave.browser; do
  run_shell "DETALHE REQUEST_INSTALL_PACKAGES $pkg" cmd appops get "$pkg" REQUEST_INSTALL_PACKAGES
done
run_shell "TECLADO PADRAO" settings get secure default_input_method
run_shell "TECLADOS DISPONIVEIS" ime list -s
for role in DIALER SMS BROWSER HOME ASSISTANT; do
  run_shell "ROLE $role" cmd role get-role-holders "android.app.role.$role"
done
for key in dialer_default_application sms_default_application assistant voice_interaction_service; do
  run_shell "FALLBACK APP PADRAO $key" settings get secure "$key"
done
run_shell "FALLBACK HOME PADRAO" cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
run_shell "FALLBACK NAVEGADOR PADRAO" cmd package resolve-activity --brief -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d https://example.invalid

for key in http_proxy global_http_proxy_host global_http_proxy_port private_dns_mode private_dns_specifier wifi_scan_always_enabled ble_scan_always_enabled; do
  run_shell "CONFIG GLOBAL $key" settings get global "$key"
done
run_shell "VPN SEMPRE ATIVA" settings get secure always_on_vpn_app
section "CONECTIVIDADE (RESUMO SEM SSID, MAC OU IP)"
CONNECTIVITY="$(adb_cmd shell dumpsys connectivity 2>&1)"
printf '%s\n' "$CONNECTIVITY" | grep -m 1 '^Active default network:' >> "$SCAN" || printf 'Rede padrao: nao identificada\n' >> "$SCAN"
if printf '%s\n' "$CONNECTIVITY" | grep -q 'state: CONNECTED/CONNECTED'; then
  printf 'Rede ativa conectada: sim\n' >> "$SCAN"
else
  printf 'Rede ativa conectada: nao confirmada\n' >> "$SCAN"
fi
if printf '%s\n' "$CONNECTIVITY" | grep -q 'NOT_VPN'; then
  printf 'Rede padrao marcada como NOT_VPN: sim\n' >> "$SCAN"
else
  printf 'Rede padrao marcada como NOT_VPN: nao confirmada\n' >> "$SCAN"
fi
if printf '%s\n' "$CONNECTIVITY" | grep -q 'UsePrivateDns: true'; then
  printf 'UsePrivateDns: true\n' >> "$SCAN"
else
  printf 'UsePrivateDns: false ou indisponivel\n' >> "$SCAN"
fi
if printf '%s\n' "$CONNECTIVITY" | grep -q 'ValidatedPrivateDnsAddresses: \[[^]]'; then
  printf 'DNS privado validado: sim (enderecos omitidos)\n' >> "$SCAN"
else
  printf 'DNS privado validado: nao confirmado\n' >> "$SCAN"
fi

run_shell "BATERIA" dumpsys battery
section "BATTERYSTATS DESDE CARGA (TRECHOS DE CONSUMO)"
adb_cmd shell dumpsys batterystats --charged 2>&1 | grep -E 'Estimated power use|Capacity:|Computed drain:|Actual drain:|Uid u[0-9]+a[0-9]+:|UID [0-9]+:' >> "$SCAN" || printf '[DADOS NAO LOCALIZADOS OU INDISPONIVEIS]\n' >> "$SCAN"
run_shell "SERVICO TERMICO" dumpsys thermalservice

section "MEMORIA DISPONIVEL"
adb_cmd shell cat /proc/meminfo 2>&1 | grep -E '^Mem(Total|Free|Available):' >> "$SCAN" || printf '[INDISPONIVEL]\n' >> "$SCAN"
section "MEMINFO - TOTAL PSS POR PROCESSO (TRECHO)"
adb_cmd shell dumpsys meminfo 2>&1 | sed -n '/Total PSS by process:/,/Total PSS by OOM adjustment:/p' >> "$SCAN" || printf '[INDISPONIVEL]\n' >> "$SCAN"
run_shell "CPUINFO (SEM PERIODO OCIOSO CONTROLADO)" dumpsys cpuinfo

run_shell "ARMAZENAMENTO /DATA" df -h /data
run_shell "DISKSTATS" dumpsys diskstats
section "PASTAS DO ARMAZENAMENTO COMPARTILHADO (NOME E TAMANHO EM MB)"
adb_cmd shell du -s -m '/storage/emulated/0/*' >> "$SCAN" 2>&1 || printf '[COMANDO INDISPONIVEL OU FALHOU]\n' >> "$SCAN"

section "PACOTES DE CAMERA/FOTO/GALERIA"
adb_cmd shell pm list packages --user 0 2>&1 | grep -Ei 'camera|photo|retouch|gallery' > "$TMP/camera_packages.txt" || true
cat "$TMP/camera_packages.txt" >> "$SCAN"
sed 's/^package://' "$TMP/camera_packages.txt" | tr -d '\r' | while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  printf '\n--- %s ---\n' "$pkg" >> "$SCAN"
  adb_cmd shell dumpsys package "$pkg" 2>&1 | grep -E 'versionName=|lastUpdateTime=' >> "$SCAN" || true
done
section "LOGCAT DE CAMERA (SOMENTE AVISOS/ERROS, ULTIMAS 3000 LINHAS)"
adb_cmd shell logcat -d -t 3000 '*:V' 2>&1 | grep -Ei '(^|[ /])(E|W)/.*(camera|photo)|camera.*(error|warn|fatal|exception)' >> "$SCAN" || printf '[SEM LINHAS CORRESPONDENTES OU INDISPONIVEL]\n' >> "$SCAN"

section "LIMITACOES DA COLETA AUTOMATICA"
printf '%s\n' '- Teste de abertura de Configuracoes nao executado: am force-stop altera estado.' >> "$SCAN"
printf '%s\n' '- CPU coletada sem confirmar 2 minutos de repouso.' >> "$SCAN"
printf '%s\n' '- Certificados de usuario, Play Protect, publicidade, sincronizacao e contas exigem verificacao manual.' >> "$SCAN"
printf '%s\n' '- Conteudo pessoal, historico, mensagens, fotos, contatos, tokens e senhas nao foram lidos.' >> "$SCAN"

rm -rf "$TMP"
printf 'Varredura concluida.\n'
