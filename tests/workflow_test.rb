require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class WorkflowTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @tmp = Dir.mktmpdir('xiaomi-test-')
    @adb = File.join(@tmp, 'adb')
    @log = File.join(@tmp, 'adb.log')
    File.write(@adb, <<~'SH')
      #!/bin/sh
      printf '%s\n' "$*" >> "$TEST_ADB_LOG"
      if [ "$1" = devices ]; then printf 'List of devices attached\nTEST device\n'; exit; fi
      shift 2
      case "$*" in
        'shell getprop ro.product.manufacturer') echo "${TEST_MAKER:-Xiaomi}" ;;
        'shell getprop ro.product.device') echo "$TEST_DEVICE" ;;
        'shell getprop ro.product.model') echo 'Test Xiaomi' ;;
        'shell getprop') printf '[ro.product.device]: [%s]\n' "$TEST_DEVICE" ;;
        'shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME') echo 'test.home/.Launcher' ;;
        'shell dumpsys window')
          if [ "${TEST_HOME_FAIL:-0}" = 1 ]; then echo 'mCurrentFocus=Window{u0 wrong.home/.Launcher}'
          else echo 'mCurrentFocus=Window{u0 test.home/.Launcher}'; fi ;;
        'shell pm list packages --user 0 com.xiaomi.midrop') echo 'package:com.xiaomi.midrop' ;;
        'shell pm uninstall --user 0 com.xiaomi.midrop') echo 'Failure [-1000]' ;;
        'shell dumpsys package com.xiaomi.midrop')
          state=0
          if [ -f "$TEST_ADB_LOG.state" ]; then state=$(cat "$TEST_ADB_LOG.state"); fi
          echo "User 0: installed=true enabled=$state" ;;
        'shell pm disable-user --user 0 com.xiaomi.midrop')
          if [ "${TEST_DISABLE_FAIL:-0}" = 1 ]; then echo 'Permission denied' >&2; exit 1; fi
          if [ "${TEST_DISABLE_LIE:-0}" != 1 ]; then printf '3' > "$TEST_ADB_LOG.state"; fi
          echo 'Package com.xiaomi.midrop new state: disabled-user' ;;
        'shell pm list packages -d --user 0 com.xiaomi.midrop')
          if [ -f "$TEST_ADB_LOG.state" ] && [ "$(cat "$TEST_ADB_LOG.state")" = 3 ]; then echo 'package:com.xiaomi.midrop'; fi ;;
        'shell pm default-state --user 0 com.xiaomi.midrop') printf '0' > "$TEST_ADB_LOG.state" ;;
        'shell pm enable --user 0 com.xiaomi.midrop') printf '1' > "$TEST_ADB_LOG.state" ;;
        'shell pm list packages --user 0 com.xiaomi.glgm'|'shell pm list packages --user 0 com.xiaomi.mipicks'|'shell pm list packages --user 0 com.mi.global.bbs'|'shell pm list packages --user 0 org.example.reader')
          if [ "${TEST_EXTRAS_PRESENT:-0}" = 1 ] && [ ! -f "$TEST_ADB_LOG.$7" ]; then echo "package:$7"; fi ;;
        'shell pm uninstall --user 0 com.xiaomi.glgm'|'shell pm uninstall --user 0 com.xiaomi.mipicks'|'shell pm uninstall --user 0 com.mi.global.bbs'|'shell pm uninstall --user 0 org.example.reader')
          printf removed > "$TEST_ADB_LOG.$6"
          echo Success ;;
        'shell settings get global '*) echo null ;;
        'shell settings put global wifi_scan_always_enabled 0')
          echo 'java.lang.SecurityException: Permission denial: writing to settings requires:android.permission.WRITE_SECURE_SETTINGS' >&2
          exit 1 ;;
        'shell pm list packages -e --user 0')
          if [ "${TEST_BAD_INVENTORY:-0}" = 1 ]; then echo 'Error: package service unavailable'; exit 0; fi
          printf 'package:android\npackage:com.chordbot\npackage:com.miui.analytics\npackage:com.xiaomi.glgm\npackage:com.xiaomi.mipicks\npackage:com.mi.global.bbs\npackage:com.xiaomi.glgm.clone\npackage:org.example.reader\n' ;;
      esac
    SH
    FileUtils.chmod(0755, @adb)
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def workflow(device, command = [], maker = 'Xiaomi')
    out = File.join(@tmp, device)
    FileUtils.mkdir_p(out)
    File.write(File.join(out, 'uad_lists.json'), JSON.generate({}))
    stdout, stderr, status = Open3.capture3(
      {'ADB' => @adb, 'TEST_ADB_LOG' => @log, 'TEST_DEVICE' => device, 'TEST_MAKER' => maker},
      'sh', File.join(ROOT, 'xiaomi_inspector.sh'), *command, '--out', out,
      stdin_data: "CANCELAR\n"
    )
    [out, stdout + stderr, status]
  end

  def test_eos_and_platina_share_default_workflow_and_preserve_chordbot
    %w[eos platina].each do |device|
      out, output, status = workflow(device)
      assert status.success?, output
      plan = File.read(File.join(out, 'app_plan.tsv'))
      assert_match(/com.chordbot\t.*\tPROTEGER\t/, plan)
      assert_match(/com.miui.analytics\t.*\tREMOVER \(aguarda aprovacao\)\t/, plan)
      assert_includes output, 'Cancelado sem alteracoes.'
    end
    refute_match(/shell (pm uninstall|reboot|settings put|cmd appops set)/, File.read(@log))
  end

  def test_all_and_full_are_aliases_of_the_same_workflow
    %w[all full].each do |command|
      _, output, status = workflow(command, [command])
      assert status.success?, output
      assert_includes output, 'APLICAR NO USUARIO 0'
    end
  end

  def test_other_manufacturer_is_rejected_before_scan
    out, output, status = workflow('other', [], 'Other')
    assert_equal 5, status.exitstatus
    assert_includes output, 'Fabricante nao suportado'
    refute File.exist?(File.join(out, 'scan.txt'))
  end

  def test_plan_rejects_results_from_another_serial
    out = File.join(@tmp, 'eos')
    FileUtils.mkdir_p(out)
    File.write(File.join(out, 'device_serial.txt'), "ANOTHER\n")
    _, output, status = workflow('eos', ['plan'])
    assert_equal 8, status.exitstatus
    assert_includes output, 'Resultados nao pertencem a este aparelho'
  end

  def shareme_cleanup(extra_env = {}, initial_state = 0)
    out = File.join(@tmp, 'resume')
    FileUtils.mkdir_p(out)
    File.write(File.join(out, 'changes.txt'), %w[A F B D C1 E].map { |g| "GRUPO #{g} CONCLUIDO\n" }.join)
    File.write(File.join(out, 'removed.txt'), '')
    File.write(File.join(out, 'app_plan.tsv'), "com.xiaomi.midrop\tShareMe\tSharing\tativo\tREMOVER (aguarda aprovacao)\n")
    File.write(@log + '.state', initial_state.to_s)
    stdout, stderr, status = Open3.capture3(
      {'TEST_ADB_LOG' => @log, 'TEST_DEVICE' => 'eos'}.merge(extra_env),
      'sh', File.join(ROOT, 'scripts/apply_cleanup.sh'), 'TEST', @adb, out, 'resume'
    )
    [out, stdout + stderr, status]
  end

  def test_resume_disables_shareme_and_records_exact_restoration
    out, output, status = shareme_cleanup
    assert status.success?, output
    assert_equal "com.xiaomi.midrop\n", File.read(File.join(out, 'disabled.txt'))
    assert_includes File.read(File.join(out, 'restore.sh')), 'pm default-state --user 0 com.xiaomi.midrop'
    assert_includes File.read(File.join(out, 'restore.bat')), 'pm default-state --user 0 com.xiaomi.midrop'
    refute File.exist?(File.join(out, 'skipped.txt'))
    assert_empty File.read(File.join(out, 'removed.txt'))
    calls = File.read(@log)
    refute_includes calls, 'trim-caches'
    refute_includes calls, 'appops set'
    assert_includes File.read(File.join(out, 'changes.txt')), 'GRUPO C2 CONCLUIDO'
  end

  def test_refused_disable_stops_without_claiming_success
    out, _, status = shareme_cleanup('TEST_DISABLE_FAIL' => '1')
    assert_equal 60, status.exitstatus
    refute File.exist?(File.join(out, 'disabled.txt'))
    assert_equal '0', File.read(@log + '.state')
  end

  def test_disable_is_checked_instead_of_trusting_command_output
    out, _, status = shareme_cleanup('TEST_DISABLE_LIE' => '1')
    assert_equal 60, status.exitstatus
    refute File.exist?(File.join(out, 'disabled.txt'))
    assert_includes File.read(File.join(out, 'changes.txt')), 'desativacao nao confirmada'
  end

  def test_launcher_failure_restores_previous_enabled_state
    out, _, status = shareme_cleanup({'TEST_HOME_FAIL' => '1'}, 1)
    assert_equal 60, status.exitstatus
    assert_equal '1', File.read(@log + '.state')
    refute File.exist?(File.join(out, 'disabled.txt'))
  end

  def test_already_disabled_shareme_has_no_reenable_command
    out, output, status = shareme_cleanup({}, 3)
    assert status.success?, output
    assert_equal "com.xiaomi.midrop\n", File.read(File.join(out, 'disabled.txt'))
    refute File.exist?(File.join(out, 'restore.sh'))
    refute_includes File.read(@log), 'shell pm disable-user'
  end

  def test_final_verification_detects_shareme_reenabled_after_fallback
    out, output, status = shareme_cleanup
    assert status.success?, output
    File.write(File.join(out, 'before.txt'), "package:com.xiaomi.midrop\n")
    env = {'TEST_ADB_LOG' => @log, 'TEST_DEVICE' => 'eos'}
    args = ['sh', File.join(ROOT, 'scripts/verify_after.sh'), 'TEST', @adb, out]
    _, _, verified = Open3.capture3(env, *args)
    assert verified.success?
    assert_includes File.read(File.join(out, 'final_verification.txt')), 'OK desativado: com.xiaomi.midrop'
    File.write(@log + '.state', '1')
    _, _, verified = Open3.capture3(env, *args)
    refute verified.success?
    assert_includes File.read(File.join(out, 'final_verification.txt')), 'FALHA desativacao: com.xiaomi.midrop'
  end

  def test_network_permission_denial_is_reported_as_pending
    out = File.join(@tmp, 'network')
    FileUtils.mkdir_p(out)
    File.write(File.join(out, 'changes.txt'), %w[A F B D C1 C2].map { |g| "GRUPO #{g} CONCLUIDO\n" }.join)
    stdout, stderr, status = Open3.capture3(
      {'TEST_ADB_LOG' => @log, 'TEST_DEVICE' => 'eos'},
      'sh', File.join(ROOT, 'scripts/apply_cleanup.sh'), 'TEST', @adb, out, 'resume'
    )
    assert status.success?, stdout + stderr
    assert_includes File.read(File.join(out, 'skipped.txt')), 'WRITE_SECURE_SETTINGS denied'
    refute_includes File.read(@log), 'settings put global private_dns_mode'
  end

  def test_invalid_inventory_stops_before_plan_and_application
    out = File.join(@tmp, 'bad_inventory')
    stdout, stderr, status = Open3.capture3(
      {'ADB' => @adb, 'TEST_ADB_LOG' => @log, 'TEST_DEVICE' => 'eos', 'TEST_BAD_INVENTORY' => '1'},
      'sh', File.join(ROOT, 'xiaomi_inspector.sh'), '--out', out, '--yes'
    )
    assert_equal 4, status.exitstatus, stdout + stderr
    refute File.exist?(File.join(out, 'app_plan.tsv'))
    refute File.exist?(File.join(out, 'changes.txt'))
  end

  def optional_plan(*selected)
    out = File.join(@tmp, 'optional')
    FileUtils.mkdir_p(out)
    packages = %w[com.xiaomi.glgm com.xiaomi.mipicks com.mi.global.bbs com.xiaomi.glgm.clone org.example.reader org.example.reader.clone]
    File.write(File.join(out, 'before.txt'), packages.map { |pkg| "package:#{pkg}\n" }.join)
    File.write(File.join(out, 'scan.txt'), '')
    File.write(File.join(out, 'uad_lists.json'), '{}')
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/build_plan.rb'), out, *selected)
    assert status.success?, stdout + stderr
    rows = File.readlines(File.join(out, 'app_plan.tsv'), chomp: true).drop(1).map { |line| line.split("\t") }
    [out, rows.to_h { |row| [row[0], row[4]] }]
  end

  def test_three_xiaomi_apps_are_removed_by_default_without_matching_other_apps
    _, recommendations = optional_plan
    %w[com.xiaomi.glgm com.xiaomi.mipicks com.mi.global.bbs].each do |pkg|
      assert_equal 'REMOVER (aguarda aprovacao)', recommendations[pkg]
    end
    refute_match(/^REMOVER/, recommendations['org.example.reader'])
    refute_match(/^REMOVER/, recommendations['com.xiaomi.glgm.clone'])
  end

  def test_cli_selection_reaches_plan_and_confirmation_without_implicit_changes
    out, output, status = workflow('eos', ['--remove-app', 'org.example.reader'])
    assert status.success?, output
    plan = File.read(File.join(out, 'app_plan.tsv'))
    assert_match(/org.example.reader\t.*\tREMOVER \(aguarda aprovacao\)\t/, plan)
    refute_match(/com.xiaomi.glgm.clone\t.*\tREMOVER/, plan)
    assert_equal "org.example.reader\n", File.read(File.join(out, 'optional_removals.txt'))
    assert_includes output, 'Remocoes opcionais selecionadas'
    refute_includes File.read(@log), 'pm uninstall'
  end

  def test_optional_removals_use_exact_selected_packages
    out, recommendations = optional_plan('com.xiaomi.glgm', 'org.example.reader', 'org.example.reader')
    assert_equal 'REMOVER (aguarda aprovacao)', recommendations['com.xiaomi.glgm']
    assert_equal 'REMOVER (aguarda aprovacao)', recommendations['com.mi.global.bbs']
    assert_equal 'REMOVER (aguarda aprovacao)', recommendations['org.example.reader']
    refute_match(/^REMOVER/, recommendations['org.example.reader.clone'])
    refute_match(/^REMOVER/, recommendations['com.xiaomi.glgm.clone'])
    assert_equal 2, File.readlines(File.join(out, 'optional_removals.txt')).length
  end

  def test_invalid_optional_package_is_rejected_before_adb
    _, output, status = Open3.capture3('sh', File.join(ROOT, 'xiaomi_inspector.sh'), '--remove-app', 'com.xiaomi.*')
    assert_equal 2, status.exitstatus
    assert_includes output, 'Nome de pacote invalido'
    refute File.exist?(@log)
  end

  def test_optional_choices_cannot_be_changed_during_apply
    _, output, status = Open3.capture3('sh', File.join(ROOT, 'xiaomi_inspector.sh'), 'apply', '--remove-app', 'com.xiaomi.glgm')
    assert_equal 2, status.exitstatus
    assert_includes output, 'ao gerar o plano'
  end

  def test_optional_group_only_removes_selected_packages_and_records_restore
    out, = optional_plan('org.example.reader')
    File.write(File.join(out, 'changes.txt'), %w[A F B D C1 C2 E].map { |g| "GRUPO #{g} CONCLUIDO\n" }.join)
    File.write(File.join(out, 'removed.txt'), "REMOVED\n\n")
    stdout, stderr, status = Open3.capture3(
      {'TEST_ADB_LOG' => @log, 'TEST_DEVICE' => 'eos', 'TEST_EXTRAS_PRESENT' => '1'},
      'sh', File.join(ROOT, 'scripts/apply_cleanup.sh'), 'TEST', @adb, out, 'resume'
    )
    assert status.success?, stdout + stderr
    calls = File.read(@log)
    assert_includes calls, 'pm uninstall --user 0 com.xiaomi.glgm'
    assert_includes calls, 'pm uninstall --user 0 com.mi.global.bbs'
    assert_includes calls, 'pm uninstall --user 0 com.xiaomi.mipicks'
    assert_includes calls, 'pm uninstall --user 0 org.example.reader'
    refute_includes calls, 'pm uninstall --user 0 org.example.reader.clone'
    assert_equal %w[com.xiaomi.glgm com.xiaomi.mipicks com.mi.global.bbs org.example.reader], File.readlines(File.join(out, 'removed.txt'), chomp: true).drop(2)
    assert_includes File.read(File.join(out, 'restore.sh')), 'install-existing --user 0 com.xiaomi.glgm'
    assert_includes File.read(File.join(out, 'restore.bat')), 'install-existing --user 0 com.mi.global.bbs'
    assert_includes File.read(File.join(out, 'restore.sh')), 'install-existing --user 0 org.example.reader'
  end

  def test_explicit_disabled_app_can_be_selected_from_the_scan
    out, = optional_plan
    File.write(File.join(out, 'scan.txt'), "===== APPS DESATIVADOS -- USER 0 =====\npackage:org.example.disabled\n\n===== APPS DE SISTEMA -- USER 0 =====\n")
    _, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/build_plan.rb'), out, 'org.example.disabled')
    assert status.success?, stderr
    assert_match(/org.example.disabled\t.*\tdesativado\tREMOVER/, File.read(File.join(out, 'app_plan.tsv')))
  end
end
