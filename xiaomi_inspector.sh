#!/bin/sh
# Xiaomi Inspector — auditoria e limpeza ADB para Xiaomi, Redmi e POCO.
#
# Este e um unico ponto de entrada para os scripts em ./scripts.
# Ele nao faz root, nao desbloqueia bootloader, nao instala ROM e nunca apaga
# arquivos pessoais. A aplicacao e deliberadamente restrita ao usuario 0.

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ADB=${ADB:-"$ROOT_DIR/platform-tools/adb"}
COMMAND=run
if [ "$#" -gt 0 ]; then
  case "$1" in -*) ;; *) COMMAND=$1; shift ;; esac
fi
SERIAL=${SERIAL:-}
OUT=${OUT:-}
ASSUME_YES=no
RESUME=no
OPTIONAL_REMOVALS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --remove-app)
      [ "$#" -ge 2 ] || { printf 'Falta o pacote de --remove-app\n' >&2; exit 2; }
      if ! printf '%s\n' "$2" | LC_ALL=C grep -Eq '^([A-Za-z][A-Za-z0-9_]*\.)*[A-Za-z][A-Za-z0-9_]*$'; then
        printf 'Nome de pacote invalido: %s\n' "$2" >&2; exit 2
      fi
      OPTIONAL_REMOVALS="$OPTIONAL_REMOVALS $2"
      shift 2
      ;;
    --yes) ASSUME_YES=yes; shift ;;
    --resume) RESUME=yes; shift ;;
    --serial)
      [ "$#" -ge 2 ] || { printf 'Falta o valor de --serial\n' >&2; exit 2; }
      SERIAL=$2
      shift 2
      ;;
    --out)
      [ "$#" -ge 2 ] || { printf 'Falta o valor de --out\n' >&2; exit 2; }
      case "$2" in
        /*) OUT=$2 ;;
        *) OUT="$ROOT_DIR/$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      COMMAND=help
      shift
      ;;
    *)
      printf 'Opcao desconhecida: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ -n "$OPTIONAL_REMOVALS" ]; then
  case "$COMMAND:$RESUME" in
    run:no|all:no|full:no|plan:no) ;;
    *) printf 'Use --remove-app ao gerar o plano (plan ou fluxo novo), nao em apply/retomada.\n' >&2; exit 2 ;;
  esac
fi

if [ -z "$OUT" ]; then
  if [ "$RESUME" = yes ]; then
    printf 'Informe --out DIRETORIO para retomar a execucao anterior.\n' >&2
    exit 2
  fi
  case "$COMMAND" in
    run|all|full) OUT="$ROOT_DIR/results/run_$(date '+%Y%m%d_%H%M%S')_$$" ;;
    *) OUT="$ROOT_DIR/results" ;;
  esac
fi

usage() {
  cat <<'EOF'
Xiaomi Inspector — auditoria e limpeza ADB

Uso:
  ./xiaomi_inspector.sh [--serial SERIAL] [--out DIRETORIO] [--yes] [--resume]
  ./xiaomi_inspector.sh status
  ./xiaomi_inspector.sh scan [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh plan [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh apply [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh reboot-verify [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh all [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh full [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh restore [--serial SERIAL] [--out DIRETORIO]
  ./xiaomi_inspector.sh report [--out DIRETORIO]

Comandos:
  status          Mostra aparelhos ADB; nao altera nada.
  scan            Varredura somente leitura e arquivos before.txt/device.txt/scan.txt.
  plan            Baixa/copia a lista publica UAD e gera app_plan.tsv localmente.
  apply           Aplica os grupos aprovados neste projeto, com confirmacao digitada.
  reboot-verify   Reinicia, espera o boot, repousa 2 minutos e verifica o resultado.
  run             Identifica -> scan -> plan -> confirmacao -> apply -> reboot -> report.
  all, full       Aliases do mesmo fluxo run (compatibilidade).
  restore         Executa o restore.sh do diretorio de resultados, com confirmacao.
  report          Mostra os artefatos e o resumo automatico da execucao.

Saida do fluxo completo: ./results/run_DATA_HORA_PID
Saida das etapas individuais: ./results (ou --out DIRETORIO)

IMPORTANTE:
  O perfil atual usa os grupos A/F/B/D/C/X/E e somente pacotes presentes.
  --yes confirma aplicacao e reinicio. Revise app_plan.tsv antes de usar.
  --resume retoma a mesma pasta/aparelho, sem repetir scan e grupos concluidos.
  Padrao: remover Centro de Jogos, Mi Picks/GetApps e Comunidade Xiaomi se presentes.
  --remove-app PACOTE: adicionar qualquer pacote exato ao plano (repetivel).
EOF
}

install_platform_tools() {
  command -v curl >/dev/null 2>&1 || {
    printf 'curl nao encontrado; ele e necessario para baixar o Platform Tools oficial.\n' >&2
    exit 3
  }
  command -v unzip >/dev/null 2>&1 || {
    printf 'unzip nao encontrado; ele e necessario para extrair o Platform Tools oficial.\n' >&2
    exit 3
  }

  case "$(uname -s)" in
    Darwin)
      archive_url='https://dl.google.com/android/repository/platform-tools-latest-darwin.zip'
      ;;
    Linux)
      archive_url='https://dl.google.com/android/repository/platform-tools-latest-linux.zip'
      ;;
    *)
      printf 'Sistema nao suportado pelo instalador automatico: %s\n' "$(uname -s)" >&2
      printf 'Instale manualmente o Platform Tools oficial em %s/platform-tools.\n' "$ROOT_DIR" >&2
      exit 3
      ;;
  esac

  if [ -d "$ROOT_DIR/platform-tools" ]; then
    printf 'A pasta platform-tools existe, mas adb nao esta executavel. Corrija ou remova a pasta incompleta.\n' >&2
    exit 3
  fi

  tmp_dir=$(mktemp -d 2>/dev/null) || {
    printf 'Nao foi possivel criar um diretorio temporario.\n' >&2
    exit 3
  }
  archive="$tmp_dir/platform-tools.zip"
  printf 'Primeira execucao: baixando o Platform Tools mais recente de dl.google.com...\n'
  if ! curl -fL "$archive_url" -o "$archive"; then
    rm -rf "$tmp_dir"
    printf 'Falha ao baixar o Platform Tools oficial.\n' >&2
    exit 3
  fi
  if ! unzip -q "$archive" -d "$tmp_dir"; then
    rm -rf "$tmp_dir"
    printf 'Falha ao extrair o Platform Tools.\n' >&2
    exit 3
  fi
  if [ ! -f "$tmp_dir/platform-tools/adb" ]; then
    rm -rf "$tmp_dir"
    printf 'O arquivo baixado nao continha platform-tools/adb.\n' >&2
    exit 3
  fi
  chmod +x "$tmp_dir/platform-tools/adb"
  mv "$tmp_dir/platform-tools" "$ROOT_DIR/platform-tools"
  rm -rf "$tmp_dir"
  printf 'Platform Tools instalado em %s/platform-tools.\n' "$ROOT_DIR"
  "$ROOT_DIR/platform-tools/adb" version | sed -n '1,3p'
}

require_adb() {
  if [ -f "$ADB" ] && [ ! -x "$ADB" ]; then chmod +x "$ADB" 2>/dev/null || true; fi
  if [ ! -x "$ADB" ]; then
    if [ "$ADB" = "$ROOT_DIR/platform-tools/adb" ]; then
      install_platform_tools
    else
      printf 'ADB personalizado nao encontrado/executavel em: %s\n' "$ADB" >&2
      exit 3
    fi
  fi
}

adb_cmd() {
  "$ADB" -s "$SERIAL" "$@" < /dev/null
}

resolve_serial() {
  require_adb
  listing=$("$ADB" devices) || exit 4
  devices=$(printf '%s\n' "$listing" | awk 'NR>1 && $2=="device" {print $1}')
  unauthorized=$(printf '%s\n' "$listing" | awk 'NR>1 && $2=="unauthorized" {print $1}')

  if [ -n "$SERIAL" ]; then
    if printf '%s\n' "$devices" | grep -qx "$SERIAL"; then return 0; fi
    if printf '%s\n' "$unauthorized" | grep -qx "$SERIAL"; then
      printf 'Aparelho %s nao autorizado. Desbloqueie e aceite "Permitir depuracao USB?".\n' "$SERIAL" >&2
      exit 4
    fi
    printf 'Aparelho %s nao esta conectado como device.\n' "$SERIAL" >&2
    exit 4
  fi

  count=$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$count" -eq 1 ]; then
    SERIAL=$(printf '%s\n' "$devices" | sed -n '1p')
  elif [ "$count" -eq 0 ]; then
    if [ -n "$unauthorized" ]; then
      printf 'Aparelho detectado, mas nao autorizado. Desbloqueie e aceite a depuracao USB.\n' >&2
    else
      printf 'Nenhum aparelho ADB conectado.\n' >&2
    fi
    exit 4
  else
    printf 'Mais de um aparelho conectado. Use --serial SERIAL.\n' >&2
    printf '%s\n' "$devices" >&2
    exit 4
  fi
}

require_xiaomi() {
  device=$(adb_cmd shell getprop ro.product.device 2>/dev/null | tr -d '\r')
  model=$(adb_cmd shell getprop ro.product.model 2>/dev/null | tr -d '\r')
  manufacturer=$(adb_cmd shell getprop ro.product.manufacturer | tr -d '\r' | tr '[:upper:]' '[:lower:]')
  case "$manufacturer" in xiaomi|redmi|poco) ;; *)
    printf 'Fabricante nao suportado: %s (%s).\n' "$manufacturer" "$model" >&2; exit 5 ;;
  esac
  printf 'Aparelho: %s (%s); perfil: current.\n' "$model" "$device"
}

require_run_device() {
  [ -f "$OUT/device_serial.txt" ] && [ "$(cat "$OUT/device_serial.txt")" = "$SERIAL" ] || {
    printf 'Resultados nao pertencem a este aparelho. Execute scan em uma pasta nova.\n' >&2
    exit 8
  }
}

check_device_owner() {
  owners=$(adb_cmd shell dumpsys device_policy 2>/dev/null | grep -Ei 'Device Owner|mDeviceOwner' | grep -Eiv 'null|none|not set|no device owner' || true)
  if [ -n "$owners" ]; then
    printf 'Possivel Device Owner detectado; aplicacao interrompida:\n%s\n' "$owners" >&2
    exit 6
  fi
}

run_scan() {
  resolve_serial
  require_xiaomi
  mkdir -p "$OUT"
  if [ -f "$OUT/device_serial.txt" ]; then require_run_device; fi
  if [ -f "$OUT/changes.txt" ]; then
    printf 'Esta pasta ja contem uma aplicacao; use --out com uma pasta nova.\n' >&2
    exit 8
  fi
  printf '%s\n' "$SERIAL" > "$OUT/device_serial.txt"
  printf 'Varredura somente leitura em %s (serial %s)...\n' "$OUT" "$SERIAL"
  sh "$ROOT_DIR/scripts/scan_android.sh" "$SERIAL" "$ADB" "$OUT"
  printf 'Revise: %s/scan.txt\n' "$OUT"
}

prepare_uad() {
  target="$OUT/uad_lists.json"
  if [ -f "$target" ]; then return 0; fi
  if [ -f "$ROOT_DIR/results/uad_lists.json" ]; then
    cp "$ROOT_DIR/results/uad_lists.json" "$target"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || { printf 'curl nao encontrado.\n' >&2; exit 7; }
  printf 'Baixando a lista publica completa do UAD-NG; nenhum dado do aparelho sera enviado...\n'
  curl -fL 'https://raw.githubusercontent.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/main/resources/assets/uad_lists.json' -o "$target"
}

run_plan() {
  resolve_serial
  require_xiaomi
  require_run_device
  [ ! -f "$OUT/changes.txt" ] || {
    printf 'O plano desta aplicacao ja foi usado; escolha uma pasta nova.\n' >&2; exit 8
  }
  [ -f "$OUT/before.txt" ] && [ -f "$OUT/scan.txt" ] || {
    printf 'Execute scan antes de plan (faltam before.txt/scan.txt em %s).\n' "$OUT" >&2
    exit 8
  }
  command -v ruby >/dev/null 2>&1 || { printf 'Ruby nao encontrado; necessario para gerar o plano.\n' >&2; exit 8; }
  prepare_uad
  # Values are validated exact package identifiers above, so splitting is intentional.
  ruby "$ROOT_DIR/scripts/build_plan.rb" "$OUT" $OPTIONAL_REMOVALS
  printf 'Revise antes de aprovar: %s/app_plan.tsv\n' "$OUT"
}

init_apply_files() {
  mkdir -p "$OUT"
  [ -f "$OUT/measurements.txt" ] || printf 'MEDIDAS ANTES E DEPOIS\n\n' > "$OUT/measurements.txt"
  [ -f "$OUT/changes.txt" ] || printf 'REGISTRO DE ALTERACOES\n\n' > "$OUT/changes.txt"
  [ -f "$OUT/removed.txt" ] || printf 'PACOTES REALMENTE REMOVIDOS DO USUARIO 0\n\n' > "$OUT/removed.txt"
  if [ ! -f "$OUT/restore.bat" ]; then
    printf '@echo off\nset ADB=..\\platform-tools\\adb.exe\nset SERIAL=%s\nrem Restauracao gerada durante a aplicacao.\n\n' "$SERIAL" > "$OUT/restore.bat"
  fi
  if [ ! -f "$OUT/restore.sh" ]; then
    printf '#!/bin/sh\nADB="%s"\nSERIAL="%s"\n# Restauracao gerada durante a aplicacao.\n\n' "$ADB" "$SERIAL" > "$OUT/restore.sh"
    chmod +x "$OUT/restore.sh"
  fi
}

show_apply_scope() {
  cat <<'EOF'
Escopo fixo desta aplicacao:
  A  negar REQUEST_INSTALL_PACKAGES em Chrome, Brave, Drive e Galeria
  F  aparar caches (nao apaga arquivos pessoais)
  B  retirar do user 0: CAIXA, My Vodafone, WhatsWeb, Disable System Apps, Google Fotos
  D  retirar MIUI System Ads e Xiaomi Analytics
  C  retirar Mi Cloud/carteira/compartilhamento Xiaomi nao usados
  X  retirar Centro de Jogos (com.xiaomi.glgm), Mi Picks (com.xiaomi.mipicks)
     e Comunidade Xiaomi (com.mi.global.bbs), se presentes
  E  desligar scans Wi-Fi/BLE e configurar dns.adguard-dns.com

ShareMe: se a remocao retornar Failure [-1000], tentar desativar no user 0.

Preservados: ChordBot, apps proprios, TeraBox, bancos mantidos, jogos, 2FA,
telefone/SMS, Camera/Galeria, conta Google e users 11/999.
EOF
  if [ -s "$OUT/optional_removals.txt" ]; then
    printf '\nRemocoes opcionais selecionadas (somente se presentes no plano):\n'
    cat "$OUT/optional_removals.txt"
  fi
}

run_apply() {
  resolve_serial
  require_xiaomi
  require_run_device
  check_device_owner
  [ -f "$OUT/app_plan.tsv" ] || {
    printf 'Execute plan e revise app_plan.tsv antes de apply.\n' >&2
    exit 9
  }
  show_apply_scope
  printf '\nMantenha o aparelho conectado, desbloqueado e sem uso durante a aplicacao.\n'
  printf '\nConfirme que o backup de fotos e conversas existe.\n'
  printf 'Para aplicar somente no usuario 0, digite exatamente: APLICAR NO USUARIO 0\n> '
  if [ "$ASSUME_YES" = yes ]; then answer='APLICAR NO USUARIO 0'; else IFS= read -r answer; fi
  [ "$answer" = 'APLICAR NO USUARIO 0' ] || { printf 'Cancelado sem alteracoes.\n'; exit 0; }
  init_apply_files
  apply_mode=full
  [ "$RESUME" = no ] || apply_mode=resume
  ENABLE_SETTINGS_BENCH=0 ENABLE_COMPILE=0 sh "$ROOT_DIR/scripts/apply_cleanup.sh" "$SERIAL" "$ADB" "$OUT" "$apply_mode"
  printf 'Aplicacao terminou. Revise %s/changes.txt antes de reiniciar.\n' "$OUT"
}

write_execution_summary() {
  summary="$OUT/execution_summary.txt"
  {
    printf 'XIAOMI INSPECTOR — RESUMO AUTOMATICO DA EXECUCAO\n'
    printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf 'Serial: %s\n\n' "$SERIAL"
    if [ -f "$OUT/device.txt" ]; then
      grep -E 'ro.product.model|ro.build.version.release|ro.build.version.security_patch|ro.boot.verifiedbootstate|ro.boot.flash.locked' "$OUT/device.txt" || true
    fi
    printf '\nMedidas registradas:\n'
    grep -E '^(=====|Data-Free:|Apps ativos user 0:|/dev/block/)' "$OUT/measurements.txt" 2>/dev/null || true
    printf '\nPacotes removidos:\n'
    sed '1,2d' "$OUT/removed.txt" 2>/dev/null || true
    printf '\nPacotes desativados pelo workaround:\n'
    if [ -f "$OUT/disabled.txt" ]; then cat "$OUT/disabled.txt"; fi
    printf '\nEtapas/pacotes preservados ou pendentes:\n'
    if [ -f "$OUT/skipped.txt" ]; then cat "$OUT/skipped.txt"; fi
    printf '\nVerificacao:\n'
    grep -E '^(sys.boot_completed|OK ausente|OK presente|OK desativado|wifi_scan|ble_scan|private_dns|DNS AdGuard|Ping)' "$OUT/final_verification.txt" 2>/dev/null || true
    printf '\nLimitacoes:\n'
    printf '%s\n' '- ADB nao prova ausencia de malware.'
    printf '%s\n' '- Testes de ligacao, SMS, banco, 2FA, Bluetooth, camera e Segundo Espaco sao manuais.'
    printf '%s\n' '- O patch Android permanece antigo e nao e corrigido por este script.'
  } > "$summary"
}

run_reboot_verify() {
  resolve_serial
  require_xiaomi
  require_run_device
  [ -f "$OUT/removed.txt" ] || { printf 'Falta removed.txt; execute apply primeiro.\n' >&2; exit 10; }
  printf 'Digite REINICIAR para reiniciar, aguardar o boot e medir apos 2 minutos:\n> '
  if [ "$ASSUME_YES" = yes ]; then answer=REINICIAR; else IFS= read -r answer; fi
  [ "$answer" = REINICIAR ] || { printf 'Reinicio cancelado.\n'; exit 0; }
  adb_cmd reboot
  printf 'Aguardando o aparelho reaparecer...\n'
  ready=no
  attempt=0
  while [ "$attempt" -lt 60 ]; do
    boot=$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
    if [ "$boot" = 1 ]; then ready=yes; break; fi
    sleep 5
    attempt=$((attempt + 1))
  done
  [ "$ready" = yes ] || { printf 'Timeout: desbloqueie o aparelho e execute reboot-verify novamente.\n' >&2; exit 11; }
  printf 'Boot concluido. Nao toque no aparelho por 120 segundos...\n'
  for idle_tick in 1 2 3 4; do
    sleep 30
    printf 'Repouso: %s/4 intervalos concluidos.\n' "$idle_tick"
  done
  sh "$ROOT_DIR/scripts/verify_after.sh" "$SERIAL" "$ADB" "$OUT"
  write_execution_summary
  printf 'Verificacao concluida: %s/final_verification.txt\n' "$OUT"
}

run_restore() {
  resolve_serial
  require_xiaomi
  require_run_device
  [ -f "$OUT/restore.sh" ] || { printf 'Falta %s/restore.sh\n' "$OUT" >&2; exit 12; }
  printf 'A restauracao reativa pacotes/permissoes registrados nessa execucao.\n'
  printf 'Digite RESTAURAR para continuar:\n> '
  IFS= read -r answer
  [ "$answer" = RESTAURAR ] || { printf 'Restauracao cancelada.\n'; exit 0; }
  (cd "$OUT" && sh ./restore.sh)
  printf 'Restauracao executada. Reinicie e teste o aparelho.\n'
}

run_report() {
  printf 'Diretorio: %s\n' "$OUT"
  for file in device_serial.txt device.txt scan.txt before.txt app_plan.tsv optional_removals.txt measurements.txt removed.txt disabled.txt skipped.txt changes.txt restore.sh restore.bat final_verification.txt execution_summary.txt summary.txt approval_plan.txt uad_lists.json; do
    if [ -f "$OUT/$file" ]; then printf '  %s\n' "$OUT/$file"; fi
  done
  if [ -f "$OUT/execution_summary.txt" ]; then
    printf '\n'
    cat "$OUT/execution_summary.txt"
  fi
}

run_workflow() {
  resolve_serial
  require_xiaomi
  if [ "$RESUME" = yes ]; then
    require_run_device
    [ -f "$OUT/changes.txt" ] && [ -f "$OUT/app_plan.tsv" ] || {
      printf 'Nao ha aplicacao para retomar nesta pasta.\n' >&2; exit 8
    }
  else
    run_scan
    run_plan
  fi
  run_apply
  run_reboot_verify
  run_report
}

case "$COMMAND" in
  help) usage ;;
  status) require_adb; "$ADB" devices -l ;;
  scan) run_scan ;;
  plan) run_plan ;;
  apply) run_apply ;;
  reboot-verify) run_reboot_verify ;;
  restore) run_restore ;;
  report) run_report ;;
  run|all|full) run_workflow ;;
  *)
    printf 'Comando desconhecido: %s\n\n' "$COMMAND" >&2
    usage >&2
    exit 2
    ;;
esac
