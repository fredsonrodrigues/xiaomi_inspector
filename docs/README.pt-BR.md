# Xiaomi Inspector

[English documentation](../README.md)

Ferramenta em shell para diagnosticar, planejar, aplicar e verificar uma limpeza controlada em aparelhos Xiaomi, Redmi e POCO, sem root.

O ponto de entrada é [`xiaomi_inspector.sh`](../xiaomi_inspector.sh). Ele coordena a varredura, gera um plano, exige aprovação antes de mudanças, registra hashes e alterações, cria scripts de restauração e comprova o estado depois do reinício.

> **Importante:** ADB não é antivírus. Este programa identifica indícios, configurações e superfícies de risco, mas não prova que o aparelho esteja livre de malware.

## Escopo e segurança

O programa:

- usa sempre `adb -s SERIAL`;
- realiza a varredura antes de permitir mudanças;
- restringe alterações ao usuário principal (`--user 0`);
- preserva o Segundo Espaço/XSpace;
- calcula SHA-256 dos APKs antes de remover pacotes;
- aplica pacotes em grupos pequenos e verifica a tela inicial;
- tenta restaurar o grupo atual se uma etapa falhar;
- registra medidas, alterações, pacotes removidos e comandos de reversão;
- não lê mensagens, fotos, contatos, senhas, tokens ou histórico de navegação;
- não envia APKs, hashes ou a lista de apps para serviços externos.

O programa **não**:

- faz root;
- desbloqueia o bootloader;
- instala ROM ou firmware;
- executa restauração de fábrica;
- apaga fotos, conversas, downloads ou outros arquivos pessoais;
- desativa Play Protect ou mecanismos de segurança do sistema;
- atualiza o patch de segurança do Android.

## Identificação automática

Xiaomi, Redmi e POCO usam o mesmo fluxo e o perfil atual. O programa identifica
fabricante, modelo e codinome; `eos` e `platina` não precisam de comandos distintos.
O suporte ao fabricante não garante compatibilidade com todos os firmwares:
uma falha interrompe o fluxo.

O perfil mantém os grupos aprovados A → F → B → D → C → E. A remoção depende
de o pacote estar instalado e marcado para remoção no plano. Apps ausentes são
ignorados, o launcher padrão é identificado e a verificação compara o inventário
inicial com as remoções registradas. Revise o plano: ele ainda representa as
escolhas do proprietário, incluindo Google Fotos, CAIXA, My Vodafone e serviços
de nuvem/compartilhamento Xiaomi.

Cada varredura grava o serial em `device_serial.txt`; as etapas seguintes
recusam resultados de outro aparelho. Use uma pasta nova por execução completa.
Uma pasta que já contém registro de aplicação não pode receber outra varredura.

## Requisitos

- macOS ou Linux com shell POSIX;
- cabo USB de dados;
- depuração USB habilitada no Android;
- `curl` e `unzip` para baixar o [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools) oficial na primeira operação que usa ADB;
- `Ruby` para gerar a tabela do plano;
- conexão com a internet na primeira execução e, se necessário, para obter a lista pública do UAD-NG.

O diretório `platform-tools/` não precisa acompanhar o projeto. Quando um comando precisar de ADB e `platform-tools/adb` ainda não existir, o Xiaomi Inspector baixa o pacote mais recente diretamente de `dl.google.com`, escolhe a versão para macOS ou Linux, extrai e valida o executável. As execuções seguintes reutilizam a versão instalada.

Estrutura esperada:

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

Depois da primeira operação com ADB, o diretório `platform-tools/` será criado automaticamente.

## Preparação do celular

1. Abra **Configurações → Sobre o telefone**.
2. Toque sete vezes em **Versão da MIUI** para habilitar as opções de desenvolvedor.
3. Abra **Configurações adicionais → Opções do desenvolvedor**.
4. Ative **Depuração USB**.
5. Conecte o cabo, desbloqueie o aparelho e aceite **“Permitir depuração USB?”**.

Confirme a conexão:

```sh
./xiaomi_inspector.sh status
```

Se houver mais de um aparelho conectado, informe o serial explicitamente:

```sh
./xiaomi_inspector.sh scan --serial 63ea88ab
```

## Uso rápido

### Fluxo completo

```sh
./xiaomi_inspector.sh
# Ou escolha a pasta explicitamente:
./xiaomi_inspector.sh --out results/meu_aparelho
```

Sem subcomando, o programa cria uma pasta exclusiva
`results/run_DATA_HORA_PID/` e executa:

```text
identificar → scan → plan → aprovação → apply → reinício → repouso → verificação → report
```

O fluxo pede confirmação antes de aplicar e reiniciar. Para uma execução já
aprovada e sem interação, use `--yes`:

```sh
./xiaomi_inspector.sh --out results/meu_aparelho --yes
```

`run`, `all` e `full` são aliases do mesmo fluxo completo.
**Mudança de comportamento:** `all` agora inclui limpeza e reinício; use `scan`
para uma auditoria somente leitura.

Se uma etapa falhar, retome no mesmo aparelho e pasta:

```sh
./xiaomi_inspector.sh --out results/meu_aparelho --resume
```

Grupos de limpeza concluídos são ignorados. Se a remoção do ShareMe
(`com.xiaomi.midrop`) retornar `Failure [-1000]` e o pacote continuar instalado,
o fluxo tenta `pm disable-user --user 0`. Ele verifica a lista de desativados e
o launcher, registra o pacote em `disabled.txt` (não em `removed.txt`) e gera
comandos para restaurar o estado de ativação anterior. Se o ShareMe já estava
desativado, mantém esse estado sem gerar comando para reativá-lo. Se a
desativação ou a verificação falhar, o grupo para e tenta reverter suas mudanças.
A verificação final também confirma que o ShareMe continua desativado.

A alternativa vale somente para o ShareMe e essa resposta de desinstalação.
Outros pacotes com `Failure [-1000]` continuam preservados em `skipped.txt`;
outros erros interrompem o fluxo. Uma retomada ignora grupos concluídos antes
dessa mudança; use uma execução nova para avaliar o perfil atualizado.
Se a primeira escrita de rede for recusada por `WRITE_SECURE_SETTINGS`, o grupo
de rede fica pendente e o fluxo continua. Configure DNS privado e scans Wi-Fi/BLE
manualmente nesse aparelho; o resumo inclui a pendência.
Para retomar uma execução automática, informe em `--out` a pasta exibida pelo
programa. As etapas individuais continuam usando `results/` por padrão.

### Apps Xiaomi padrão e remoções adicionais

Estes apps entram na limpeza por padrão. Se o pacote não existir, o fluxo segue:

| App | Pacote |
|---|---|
| Centro de Jogos | `com.xiaomi.glgm` |
| Mi Picks / GetApps | `com.xiaomi.mipicks` |
| Comunidade Xiaomi | `com.mi.global.bbs` |

```sh
./xiaomi_inspector.sh
```

Para adicionar qualquer outro app instalado, repita `--remove-app` com o pacote
completo. Não há lista restrita de pacotes. Exemplo (substitua os nomes):

```sh
./xiaomi_inspector.sh --remove-app org.example.reader --remove-app com.example.other
```

O comando executa o fluxo completo com suas confirmações. A seleção explícita
prevalece sobre as classificações de manter/proteger; revise pacote, dependências
e dados locais antes de confirmar. Para apenas revisar, execute
`scan --out results/revisao` e depois
`plan --out results/revisao --remove-app org.example.reader`.

As escolhas adicionais ficam em `optional_removals.txt`. O plano usa nomes
exatos presentes no inventário, incluindo apps desativados selecionados
explicitamente. Pacotes ausentes são ignorados. Nomes inválidos, curingas,
espaços e expressões de shell são rejeitados. O grupo adicional usa os mesmos registros,
validação do launcher, reversão e verificação final dos demais grupos.
Selecione durante `plan` ou uma execução nova; `apply` e `--resume` usam o plano
salvo e não aceitam novas escolhas.

A investigação dos domínios está em
[Endpoint audit — 2026-11-12](network/ENDPOINT_AUDIT_2026-11-12.md).

### Execução por etapas

```sh
./xiaomi_inspector.sh scan --out results_new_run
./xiaomi_inspector.sh plan --out results_new_run
./xiaomi_inspector.sh apply --out results_new_run
./xiaomi_inspector.sh reboot-verify --out results_new_run
./xiaomi_inspector.sh report --out results_new_run
```

Usar etapas separadas é o modo recomendado: permite revisar `scan.txt` e `app_plan.tsv` antes da aplicação.

## Comandos

### `status`

Lista os aparelhos ADB conectados. Não altera nada.

```sh
./xiaomi_inspector.sh status
```

### `scan`

Executa uma coleta somente leitura:

- identidade e integridade do boot;
- patch de segurança;
- Device Owner e administradores;
- apps ativos, desativados, de sistema e de terceiros;
- instaladores, datas, permissões e poderes especiais;
- acessibilidade, leitores de notificações e sobreposição;
- proxy, VPN, DNS e scans Wi-Fi/BLE;
- bateria, temperatura, memória, CPU e armazenamento;
- pacotes e logs filtrados de câmera.

```sh
./xiaomi_inspector.sh scan --out results_new_run
```

O bloco de rede é sanitizado para não armazenar SSID, BSSID, MAC ou IP.

### `plan`

Gera `app_plan.tsv` com todos os pacotes ativos e uma classificação:

- `PROTEGER`;
- `SUSPEITO`;
- `REMOVER (aguarda aprovação)`;
- `MANTER NA DÚVIDA`.

```sh
./xiaomi_inspector.sh plan --out results_new_run
```

O programa usa a lista pública completa do [Universal Android Debloater Next Generation](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation) apenas como referência local. A lista do aparelho não é enviada ao projeto UAD.

Uma indicação `Recommended` do UAD não autoriza remoção automática. Apps não confirmados permanecem instalados.

### `apply`

Aplica apenas o plano fixo aprovado neste projeto. Antes de começar, exige a frase:

```text
APLICAR NO USUARIO 0
```

```sh
./xiaomi_inspector.sh apply --out results_new_run
```

Mantenha o celular conectado, desbloqueado e sem uso durante a aplicação.

#### Grupos aplicados

| Grupo | Ação |
|---|---|
| A | Nega `REQUEST_INSTALL_PACKAGES` em Chrome, Brave, Google Drive e Galeria MIUI |
| F | Apara caches; não apaga arquivos pessoais ou dados de login |
| B | Retira do usuário 0 CAIXA, My Vodafone, WhatsWeb, Disable System Apps e Google Fotos |
| D | Retira MIUI System Ads e Xiaomi Analytics |
| C | Retira componentes não usados de Mi Cloud, carteira e compartilhamento Xiaomi |
| E | Desliga scans permanentes Wi-Fi/BLE e configura `dns.adguard-dns.com` |

São preservados intencionalmente:

- ChordBot;
- apps próprios;
- TeraBox;
- bancos mantidos;
- jogos;
- autenticador 2FA;
- telefone, SMS, contatos, câmera, galeria e teclado;
- conta e serviços Google;
- usuários 11 e 999 do Segundo Espaço/XSpace.

O benchmark que usa `am force-stop` fica desativado porque foi bloqueante nesta versão da MIUI. A compilação `speed-profile` também fica desativada por padrão porque não apresentou conclusão verificável na execução original.

### `reboot-verify`

Exige a palavra `REINICIAR`, reinicia o telefone, espera `sys.boot_completed=1`, mantém dois minutos de repouso e repete as verificações.

```sh
./xiaomi_inspector.sh reboot-verify --out results_new_run
```

Depois, teste manualmente:

- ligação e SMS;
- Gboard;
- Wi-Fi e Brave;
- Bluetooth;
- câmera, galeria e compartilhamento;
- TeraBox;
- banco e autenticador 2FA;
- jogo;
- Segundo Espaço.

### `report`

Mostra os arquivos disponíveis e o resumo automático:

```sh
./xiaomi_inspector.sh report --out results_new_run
```

Para consultar a execução original deste projeto:

```sh
./xiaomi_inspector.sh report --out results
```

### `restore`

Executa o `restore.sh` gerado durante a aplicação. Exige a palavra `RESTAURAR`.

```sh
./xiaomi_inspector.sh restore --out results_new_run
```

A restauração reativa pacotes e permissões registradas, mas não garante a recuperação dos dados locais de apps de terceiros. Depois de restaurar, reinicie e teste o aparelho.

## Opções e variáveis

As opções podem ser usadas em qualquer etapa aplicável:

```sh
--serial SERIAL
--out DIRETORIO
--yes       # Confirma aplicação e reinício numa execução já aprovada
--resume    # Retoma a execução no mesmo aparelho e pasta
--remove-app PACOTE # Seleção opcional; pode ser repetida
```

Também é possível definir:

```sh
ADB=/caminho/para/adb
SERIAL=serial_do_aparelho
OUT=/caminho/para/results
```

Exemplo:

```sh
ADB=/opt/android/platform-tools/adb \
SERIAL=63ea88ab \
OUT="$PWD/results_test" \
./xiaomi_inspector.sh scan
```

## Arquivos gerados

| Arquivo | Conteúdo |
|---|---|
| `device_serial.txt` | Vincula a execução ao aparelho escaneado |
| `device.txt` | Propriedades filtradas do aparelho; não publicar |
| `scan.txt` | Coleta ADB bruta e sanitizada |
| `before.txt` | Pacotes ativos antes da aplicação |
| `uad_lists.json` | Cópia local da lista pública UAD-NG |
| `app_plan.tsv` | Classificação dos pacotes ativos |
| `optional_removals.txt` | Pacotes opcionais selecionados na geração do plano |
| `measurements.txt` | Armazenamento, RAM, temperatura e contagens antes/depois |
| `changes.txt` | Comandos, resultados e hashes SHA-256 |
| `removed.txt` | Apenas pacotes efetivamente removidos do usuário 0 |
| `disabled.txt` | Pacotes instalados, mas desativados pelo workaround do ShareMe |
| `skipped.txt` | Remoções recusadas e configurações pendentes |
| `restore.sh` | Reversão para macOS/Linux |
| `restore.bat` | Reversão para Windows |
| `final_verification.txt` | Verificações após o reinício |
| `execution_summary.txt` | Resumo automático da execução |

Use uma pasta de resultados diferente para cada execução importante:

```sh
./xiaomi_inspector.sh --out "results/run_$(date +%Y%m%d_%H%M%S)"
```

## Privacidade

O programa não deve ser usado para coletar conteúdo pessoal. A varredura registra nomes de pacotes, permissões, estados, tamanhos e contagens.

Não publique `device.txt`, `changes.txt` ou a varredura completa sem revisão. Eles podem conter informações técnicas úteis para identificar a configuração do dispositivo.

## Solução de problemas

### `unauthorized`

Desbloqueie o celular e aceite **“Permitir depuração USB?”**. Se a janela não aparecer, desconecte e reconecte o cabo com a tela desbloqueada.

### Nenhum aparelho aparece

- teste outro cabo de dados;
- escolha o modo USB **Transferência de arquivos**;
- confirme que a Depuração USB continua ativa;
- execute `./platform-tools/adb kill-server` e tente novamente.

### Mais de um aparelho conectado

Use `--serial` em todos os comandos:

```sh
./xiaomi_inspector.sh scan --serial SERIAL --out results_serial
```

### Device Owner detectado

O programa interrompe `apply`. Um Device Owner pode indicar gerenciamento empresarial ou escolar; não contorne essa proteção sem confirmar a propriedade e a política do aparelho.

### DNS AdGuard bloqueou um serviço legítimo

Use a restauração gerada ou volte manualmente ao DNS oportunista:

```sh
./platform-tools/adb -s SERIAL shell settings put global private_dns_mode opportunistic
./platform-tools/adb -s SERIAL shell settings delete global private_dns_specifier
```

### Uma atualização reinstalou pacotes

Atualizações da MIUI podem reativar ou reinstalar componentes. Execute uma nova `scan`, compare o plano e não aplique remoções cegamente.

## Limitações conhecidas

- ADB não confirma ausência de vírus ou spyware.
- O patch de segurança permanece em `2020-08-01`; limpeza de apps não corrige Android, kernel, modem ou drivers Qualcomm.
- Saúde percentual real da bateria pode não estar disponível sem diagnóstico do fabricante.
- `dumpsys batterystats`, `diskstats` e `cpuinfo` podem apresentar dados antigos ou janelas de medição inconsistentes.
- O tempo de abertura de Configurações não é medido nesta MIUI.
- Anúncios, rastreamento e autonomia precisam ser observados por vários dias.
- O modo anônimo não esconde o IP nem evita rastreamento associado a contas, VPN, proxy, certificados ou apps privilegiados.

## Validação do código

Verifique a sintaxe antes de executar:

```sh
sh -n xiaomi_inspector.sh
sh -n scripts/scan_android.sh
sh -n scripts/apply_cleanup.sh
sh -n scripts/verify_after.sh
```

O executável e os scripts auxiliares passaram em `sh -n`. O projeto não depende de root e não contém operações de flash ou desbloqueio de bootloader.

