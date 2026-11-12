#!/usr/bin/env ruby
require "json"
require "set"

root = ARGV[0] || "results"
default_xiaomi_apps = {
  "com.xiaomi.glgm" => ["Centro de Jogos", "Xiaomi Game Center / Xiaomi Games"],
  "com.xiaomi.mipicks" => ["Mi Picks / GetApps", "Loja de aplicativos Xiaomi"],
  "com.mi.global.bbs" => ["Comunidade Xiaomi", "Comunidade e forum Xiaomi"]
}
optional_selected = ARGV.drop(1).uniq
invalid = optional_selected.reject { |pkg| pkg.match?(/\A(?:[A-Za-z][A-Za-z0-9_]*\.)*[A-Za-z][A-Za-z0-9_]*\z/) }
abort "Nomes de pacotes invalidos: #{invalid.join(', ')}" unless invalid.empty?
active = File.readlines(File.join(root, "before.txt"), chomp: true).grep(/^package:/).map { |x| x.sub("package:", "") }
scan = File.read(File.join(root, "scan.txt"))
disabled_block = scan[/===== APPS DESATIVADOS -- USER 0 =====\n(.*?)\n===== APPS DE SISTEMA/m, 1] || ""
disabled = disabled_block.lines.grep(/^package:/).map { |line| line.strip.sub("package:", "") }
active = (active + ((optional_selected + default_xiaomi_apps.keys) & disabled)).uniq
uad = JSON.parse(File.read(File.join(root, "uad_lists.json")))

third_block = scan[/===== APPS DE TERCEIROS -- USER 0 =====\n(.*?)\n===== INSTALADORES/m, 1] || ""
third = third_block.lines.grep(/^package:/).map { |x| x.strip.sub("package:", "") }.to_set

known = {
  "android" => ["Android", "Nucleo do sistema operacional"],
  "com.android.camera" => ["Camera", "Camera principal da MIUI"],
  "com.miui.gallery" => ["Galeria MIUI", "Galeria, edicao e integracao de fotos"],
  "com.miui.mediaeditor" => ["Editor de midia MIUI", "Editor usado pela Galeria"],
  "com.google.android.apps.photos" => ["Google Fotos", "Fotos, backup e edicao"],
  "com.google.android.apps.authenticator2" => ["Google Authenticator", "Codigos de autenticacao em duas etapas"],
  "com.android.vending" => ["Google Play Store", "Loja e atualizacoes de apps"],
  "com.google.android.gms" => ["Google Play Services", "Servicos essenciais do Google"],
  "com.google.android.gsf" => ["Google Services Framework", "Base dos servicos Google"],
  "com.google.android.inputmethod.latin" => ["Gboard", "Teclado padrao"],
  "com.brave.browser" => ["Brave", "Navegador padrao atual"],
  "com.android.chrome" => ["Chrome", "Navegador instalado"],
  "com.android.mms" => ["Mensagens MIUI", "App de SMS padrao"],
  "com.miui.home" => ["Launcher MIUI", "Tela inicial padrao"],
  "com.google.android.googlequicksearchbox" => ["Google", "Pesquisa e assistente padrao"],
  "com.xiaomi.finddevice" => ["Encontrar dispositivo Xiaomi", "Localizacao e protecao antirroubo"],
  "com.xiaomi.account" => ["Conta Xiaomi", "Conta do fabricante"],
  "com.miui.msa.global" => ["MIUI System Ads", "Publicidade/personalizacao da MIUI"],
  "com.miui.analytics" => ["Xiaomi Analytics", "Telemetria da Xiaomi"],
  "com.mi.android.globalminusscreen" => ["App Vault", "Painel lateral/esquerdo da MIUI"],
  "com.facebook.appmanager" => ["Facebook App Manager", "Atualizacao/servicos Meta pre-instalados"],
  "com.facebook.services" => ["Facebook Services", "Servicos Meta pre-instalados"],
  "com.facebook.system" => ["Facebook System", "Instalador/servicos Meta pre-instalados"],
  "com.dubox.drive" => ["TeraBox", "Armazenamento em nuvem; ativo em segundo plano"],
  "br.com.gabba.Caixa" => ["CAIXA", "Banco; leitor de notificacoes antiphishing ativo"],
  "com.vodafone.mCare" => ["My Vodafone", "App da operadora; sobreposicao permitida"],
  "com.chordbot" => ["Chordbot", "App musical instalado por APK"],
  "com.adsum.qpagapp" => ["QPag", "App instalado por APK; funcao nao confirmada"],
  "com.adsum.multi_checker_2" => ["Multi Checker 2", "App instalado por APK; funcao nao confirmada"],
  "com.adsum.duobusmobile" => ["Duobus Mobile", "App instalado por APK; funcao nao confirmada"],
  "com.adsum.betadelivery" => ["Beta Delivery", "App instalado por APK; localizacao concedida"],
  "com.imesc.imescquestionario" => ["IMESC Questionario", "Instalador nao registrado; funcao a confirmar"],
  "com.learnpainless.disable_system_apps" => ["Disable System Apps", "Utilitario para abrir/desativar apps do sistema"],
  "com.geeksoftapps.whatsweb" => ["WhatsWeb", "Cliente/espelhamento de WhatsApp; listener declarado mas nao ativo"],
  "com.cyworld.camera" => ["Cymera", "Camera e editor de fotos de terceiros"],
  "com.jacksoftw.webcam" => ["Webcam", "Uso do celular como webcam"],
}

protected_exact = Set.new(%w[
  android com.android.systemui com.android.settings com.android.phone com.android.server.telecom
  com.android.contacts com.android.providers.contacts com.android.providers.telephony
  com.android.mms com.android.mms.service com.android.incallui com.android.camera com.miui.gallery
  com.miui.mediaeditor com.android.vending com.google.android.gms com.google.android.gsf
  com.google.android.inputmethod.latin com.google.android.webview com.google.android.packageinstaller
  com.google.android.permissioncontroller com.google.android.apps.authenticator2 com.brave.browser
  com.miui.home com.google.android.googlequicksearchbox com.xiaomi.finddevice com.miui.securitycenter
  com.miui.powerkeeper com.lbe.security.miui com.goodix.fingerprint com.xiaomi.account
  com.adsum.qpagapp com.adsum.multi_checker_2 com.adsum.duobusmobile com.adsum.betadelivery
  com.chordbot com.dev.adsum com.imesc.imescquestionario com.dubox.drive com.dts.freefireth
  com.gamestar.pianoperfect com.firsttouchgames.dls7 com.google.android.play.games
])
known.merge!(default_xiaomi_apps)

protected_patterns = [
  /^com\.android\.providers\./, /^com\.android\.networkstack/, /^com\.google\.android\.overlay\./,
  /^com\.qualcomm\.qti\.(telephony|ims)/, /^org\.codeaurora\.ims/,
  /authenticator/i, /(^|\.)bank/i, /^com\.itau$/, /^br\.com\.bb\./, /^com\.nu\./,
  /^pt\.novobanco\./, /^br\.gov\.caixa\./, /^com\.transferwise\./, /^com\.paypal\./,
  /^com\.coinbase\./, /^br\.com\.digio$/, /^br\.com\.modalmais$/,
]

suspicious = Set.new

remove_confirmed = Set.new(%w[
  br.com.gabba.Caixa com.vodafone.mCare com.geeksoftapps.whatsweb
  com.learnpainless.disable_system_apps com.google.android.apps.photos
  com.miui.msa.global com.miui.analytics com.miui.cloudbackup com.miui.micloudsync
  com.miui.cloudservice com.miui.cloudservice.sysbase com.xiaomi.payment com.mipay.wallet.id
  com.xiaomi.midrop com.miui.mishare.connectivity com.xiaomi.mi_connect_service
  com.xiaomi.miplay_client com.milink.service
])
remove_confirmed.merge(optional_selected)
remove_confirmed.merge(default_xiaomi_apps.keys)

def safe_tsv(value)
  value.to_s.gsub(/[\t\r\n]+/, " ").strip
end

out = File.join(root, "app_plan.tsv")
File.open(out, "w") do |f|
  f.puts ["pacote", "nome", "funcao", "estado", "recomendacao", "risco", "como_voltar"].join("\t")
  active.sort.each do |pkg|
    u = uad[pkg] || {}
    first_desc = u.fetch("description", "").split("\n").first.to_s
    name, function = known.fetch(pkg, [pkg, first_desc.empty? ? "Funcao nao confirmada nesta varredura" : first_desc])

    if remove_confirmed.include?(pkg)
      recommendation = "REMOVER (aguarda aprovacao)"
      risk = optional_selected.include?(pkg) ? "Remocao explicita do cliente; revisar dependencias e dados locais, somente usuario 0" : "Perfil padrao aprovado; revisar dependencias e remover somente do usuario 0"
      back = third.include?(pkg) ? "Reinstalar pela loja/backup ou install-existing se permanecer noutro usuario" : "cmd package install-existing --user 0 #{pkg}"
    elsif suspicious.include?(pkg)
      recommendation = "SUSPEITO"
      risk = "Exige confirmacao do dono antes de manter poderes ou desinstalar"
      back = third.include?(pkg) ? "Reinstalar da fonte confiavel/backup; dados podem nao voltar" : "cmd package install-existing --user 0 #{pkg}"
    elsif protected_exact.include?(pkg) || protected_patterns.any? { |pattern| pattern.match?(pkg) }
      recommendation = "PROTEGER"
      risk = "Alto risco funcional ou de perda de acesso/dados se removido"
      back = "Nao remover"
    elsif u["removal"] == "Recommended"
      recommendation = "MANTER NA DUVIDA (candidato UAD Recommended)"
      risk = "Depende do uso; a lista UAD nao substitui confirmacao neste aparelho"
      back = third.include?(pkg) ? "Reinstalar pela loja/backup" : "cmd package install-existing --user 0 #{pkg}"
    else
      recommendation = "MANTER NA DUVIDA"
      risk = third.include?(pkg) ? "App do usuario; confirmar necessidade e backup" : "Funcao/dependencias nao confirmadas"
      back = third.include?(pkg) ? "Reinstalar pela loja/backup" : "cmd package install-existing --user 0 #{pkg}"
    end

    f.puts [pkg, name, function, disabled.include?(pkg) ? "desativado" : "ativo", recommendation, risk, back].map { |x| safe_tsv(x) }.join("\t")
  end
end

puts "Plano criado: #{out} (#{active.length} pacotes)"
File.write(File.join(root, "optional_removals.txt"), optional_selected.map { |pkg| "#{pkg}\n" }.join)
