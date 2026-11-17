"""Run real installer/cleanup shell flows against isolated old/new firmware fixtures."""
import ast
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GOOGLE = ROOT.name.startswith('degoogler')


class ModuleTests(unittest.TestCase):
    def test_kernel_su_archive_uses_custom_installer_protocol(self):
        tree = ast.parse((ROOT / 'build.py').read_text())
        files = next(ast.literal_eval(node.value) for node in tree.body
                     if isinstance(node, ast.Assign) and any(
                         isinstance(target, ast.Name) and target.id == 'files' for target in node.targets))
        # install.sh selects KernelSU's legacy protocol and bypasses customize.sh.
        self.assertNotIn('install.sh', files)
        self.assertTrue({'customize.sh', 'configure.sh', 'lib.sh', 'targets.txt',
                         'trusted-signers.txt', 'package-probe.dex'} <= set(files))

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.stage = self.work / 'stage'
        shutil.copytree(ROOT, self.stage, ignore=shutil.ignore_patterns('.git', 'tests'))
        self.active = self.work / 'active'
        self.state = self.work / 'state'
        self.virtual = self.work / 'virtual'
        self.probes = self.work / 'probes'
        self.probes.mkdir()
        self.keys = self.work / 'keys'
        self.keys.write_text('')
        # Bind the production shell's absolute Android data paths inside this fixture.
        library = (self.stage / 'lib.sh').read_text()
        for prefix in ['/data/app/', '/data/user/0', '/data/user_de/0']:
            library = library.replace(prefix, str(self.virtual) + prefix)
        (self.stage / 'lib.sh').write_text(library)
        self.rows = [line.split('|') for line in (ROOT / 'targets.txt').read_text().splitlines()]
        self.signers = dict(line.split('|') for line in (ROOT / 'trusted-signers.txt').read_text().splitlines())
        self.package = self.rows[0][0]

    def run_shell(self, body, keys=(), before='', success=True):
        self.keys.write_text('\n'.join(keys) + ('\n' if keys else ''))
        wrapper = r'''
MODPATH="$TEST/stage"; ACTIVE="$TEST/active"; WL="$TEST/state"
. "$MODPATH/lib.sh"
ui_print() { echo "$*"; }
abort() { echo "$*"; exit 60; }
getkey() {
  local answer
  answer=$(head -n 1 "$TEST/keys")
  sed '1d' "$TEST/keys" > "$TEST/keys.next"
  mv "$TEST/keys.next" "$TEST/keys"
  echo "${answer:-none}"
}
is_whiteout() { [ -f "$1" ]; }
mknod() { : > "$1"; }
real_path() { echo "$TEST/firmware/$1"; }
probe() {
  [ ! -f "$TEST/probes/$1.error" ] || return 1
  if [ -f "$TEST/probes/$1" ]; then cat "$TEST/probes/$1"; else echo state=absent; fi
}
pm() {
  echo "$*" >> "$TEST/pm-calls"
  if [ -f "$TEST/fail-uninstall" ]; then echo Failure; return 1; fi
  local pkg="$4"
  [ "$1" = uninstall ] && [ "$2" = --versionCode ] && [ "$3" = 10 ] || return 1
  echo state=absent > "$TEST/probes/$pkg"
  echo Success
}
'''
        result = subprocess.run(['sh', '-c', wrapper + '\n' + before + '\n' + body],
                                env={**os.environ, 'TEST': str(self.work)}, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def install(self, keys=(), **kwargs):
        return self.run_shell('. "$MODPATH/configure.sh"', keys, **kwargs)

    def select_only(self, pkg=None):
        pkg = pkg or self.package
        row = next(row for row in self.rows if row[0] == pkg)
        (self.stage / 'selected-targets').write_text('|'.join(row[:3]) + '|\n')

    def observe(self, pkg=None, signer=None, stock=False, split=False):
        pkg = pkg or self.package
        base = self.virtual / ('system' if stock else 'data/app') / pkg / 'base.apk'
        base.parent.mkdir(parents=True, exist_ok=True)
        base.write_bytes(b'signed package fixture')
        paths = [base]
        if split:
            other = base.with_name('split.apk')
            other.write_bytes(b'signed split fixture')
            paths.append(other)
        fingerprint = hashlib.sha256(''.join(str(p) for p in paths).encode()).hexdigest()
        observation = ('state=present\npackage=' + pkg + '\nsigners=' + (signer or self.signers[pkg])
                       + '\nbase=' + str(base) + '\nversion=10\n'
                       + ''.join('apk=' + str(p) + '\n' for p in paths)
                       + 'fingerprint=' + fingerprint + '\n')
        (self.probes / pkg).write_text(observation)
        return fingerprint

    def selections(self):
        return dict(line.split('=', 1) for line in (self.stage / 'selections').read_text().splitlines())

    def selected(self):
        return {line.split('|')[0] for line in (self.stage / 'selected-targets').read_text().splitlines()}

    def test_first_install_defaults(self):
        self.install(['up'] if GOOGLE else [])
        if GOOGLE:
            self.assertEqual(self.selections(), {'choice': 'A', 'intelligence': 'no', 'auto': 'no'})
            self.assertEqual(len(self.selected()), 3)
        else:
            self.assertTrue(all(value == 'no' for value in self.selections().values()))
            self.assertEqual(self.selected(), set())

    def test_prior_config_is_preserved_on_timeout(self):
        self.active.mkdir()
        config = ('choice=C\nintelligence=yes\nauto=no\n' if GOOGLE else
                  ''.join(row[0] + '=' + ('yes' if i % 2 else 'no') + '\n' for i, row in enumerate(self.rows)))
        (self.active / 'selections').write_text(config)
        self.install()
        self.assertEqual((self.stage / 'selections').read_text(), config)

    def test_legacy_whiteouts_are_preserved(self):
        self.active.mkdir()
        row = next(row for row in self.rows if row[0] == 'com.google.android.gms') if GOOGLE else self.rows[7]
        path = self.active / row[2].split()[0]
        path.parent.mkdir(parents=True)
        path.touch()
        self.install()
        self.assertIn(row[0], self.selected())
        if GOOGLE:
            self.assertEqual(self.selections()['choice'], 'B')
            self.assertIn('com.google.android.as', self.selected())
        else:
            overlay = self.stage / row[2].split()[1]
            self.assertTrue(overlay.is_file())

    def test_kept_choices_do_not_leak_old_hook_state(self):
        self.active.mkdir()
        self.state.mkdir()
        (self.state / 'facelock_off').touch()
        (self.state / 'stop_linkturbo').touch()
        self.install(['down', 'up'] if GOOGLE else ['down'])
        self.assertFalse((self.stage / 'face').exists())
        self.assertFalse((self.stage / 'lt').exists())

    def test_old_firmware_absent_paths_are_covered(self):
        # Empty stock tree models old firmware for targets introduced by the OTA.
        self.install(['down', 'up', 'up'] if GOOGLE else ['up'] * len(self.rows))
        for line in (self.stage / 'selected-targets').read_text().splitlines():
            for path in line.split('|')[2].split():
                self.assertTrue((self.stage / path).is_file(), path)
        if GOOGLE:
            self.assertEqual(len(self.selected()), 16)
            self.assertTrue((self.stage / 'system/product/overlay/GmsConfigOverlayASI.apk').exists())
        else:
            self.assertEqual(len(self.selected()), 17)
            self.assertTrue((self.stage / 'system/product/overlay/RuntimeTest__ussi_arm64_go__auto_generated_rro_product.apk').exists())

    def test_new_firmware_present_paths_are_covered(self):
        for row in self.rows:
            for path in row[2].split():
                stock = self.work / 'firmware' / path
                stock.parent.mkdir(parents=True, exist_ok=True)
                stock.touch()
        result = self.install(['down', 'up', 'up'] if GOOGLE else ['up'] * len(self.rows))
        self.assertNotIn('(0 present,', result.stdout)

    def test_reconfiguration_discards_stale_staged_whiteouts(self):
        stale = self.stage / 'system/app/OldSelection'
        stale.parent.mkdir(parents=True)
        stale.touch()
        (self.stage / 'face').touch()
        (self.stage / 'lt').touch()
        self.install(['up'] if GOOGLE else [])
        self.assertFalse(stale.exists())
        self.assertFalse((self.stage / 'face').exists())
        self.assertFalse((self.stage / 'lt').exists())

    def test_package_setting_is_literal(self):
        config = self.work / 'config'
        config.write_text('comXgoogleXandroid=no\ncom.google.android=yes\n')
        result = self.run_shell('setting "$TEST/config" com.google.android')
        self.assertEqual(result.stdout.strip(), 'yes')

    def test_cleanup_backs_up_base_and_splits(self):
        fingerprint = self.observe(split=True)
        self.select_only()
        self.run_shell('cleanup_targets')
        backup = self.state / 'backups' / self.package / fingerprint
        self.assertTrue((backup / 'complete').exists())
        self.assertTrue((backup / '0.apk').exists())
        self.assertTrue((backup / '1.apk').exists())
        self.assertEqual((self.probes / self.package).read_text().strip(), 'state=absent')
        self.assertEqual((self.state / 'cleanup-pending').read_text(), '')

    def test_unrecognized_replacement_is_kept(self):
        self.observe(signer='a' * 64)
        self.select_only()
        result = self.run_shell('cleanup_targets')
        self.assertIn('replacement or unrecognized signer kept', result.stdout)
        self.assertFalse((self.work / 'pm-calls').exists())

    def test_verified_signing_rotation_is_accepted(self):
        self.observe(signer='a' * 64)
        path = self.probes / self.package
        path.write_text(path.read_text() + 'lineage=' + self.signers[self.package] + ',' + 'a' * 64 + '\n')
        self.select_only()
        self.run_shell('cleanup_targets')
        self.assertTrue((self.work / 'pm-calls').exists())

    def test_multisigner_subset_is_not_accepted_as_rotation(self):
        self.observe(signer=self.signers[self.package] + ',' + 'a' * 64)
        path = self.probes / self.package
        path.write_text(path.read_text() + 'lineage=' + self.signers[self.package] + '\n')
        self.select_only()
        self.run_shell('cleanup_targets')
        self.assertFalse((self.work / 'pm-calls').exists())

    def test_untrusted_rotation_history_is_kept(self):
        self.observe(signer='a' * 64)
        path = self.probes / self.package
        path.write_text(path.read_text() + 'lineage=' + 'b' * 64 + '\n')
        self.select_only()
        self.run_shell('cleanup_targets')
        self.assertFalse((self.work / 'pm-calls').exists())

    def test_stock_visible_is_pending_without_uninstall(self):
        self.observe(stock=True)
        self.select_only()
        self.run_shell('cleanup_targets', success=False)
        self.assertIn('stock APK still visible', (self.state / 'cleanup-pending').read_text())
        self.assertFalse((self.work / 'pm-calls').exists())

    def test_failed_cleanup_retries(self):
        self.observe()
        self.select_only()
        failure = self.work / 'fail-uninstall'
        failure.touch()
        self.run_shell('cleanup_targets', success=False)
        self.assertIn('retry next boot', (self.state / 'cleanup-pending').read_text())
        failure.unlink()
        self.run_shell('cleanup_targets')
        self.assertEqual((self.state / 'cleanup-pending').read_text(), '')

    def test_backup_failure_never_uninstalls(self):
        self.observe()
        self.select_only()
        self.run_shell('cleanup_targets', before='backup_package() { return 1; }', success=False)
        self.assertFalse((self.work / 'pm-calls').exists())
        self.assertIn('backup or identity check failed', (self.state / 'cleanup-pending').read_text())

    def test_changed_identity_never_uninstalls(self):
        self.observe()
        self.select_only()
        self.run_shell('cleanup_targets', before='''
backup_package() {
  sed 's/version=10/version=11/' "$TEST/probes/$1" > "$TEST/probes/$1.next"
  mv "$TEST/probes/$1.next" "$TEST/probes/$1"
}
''', success=False)
        self.assertFalse((self.work / 'pm-calls').exists())

    def test_inspection_failure_remains_pending(self):
        self.select_only()
        (self.probes / (self.package + '.error')).touch()
        self.run_shell('cleanup_targets', success=False)
        self.assertIn('inspection failed', (self.state / 'cleanup-pending').read_text())

    def test_missing_apps_do_not_trigger_uninstalls(self):
        self.select_only()
        self.run_shell('cleanup_targets')
        self.assertFalse((self.work / 'pm-calls').exists())

    def test_failed_install_does_not_touch_previous_choices(self):
        self.active.mkdir()
        old = 'choice=B\n' if GOOGLE else self.package + '=yes\n'
        (self.active / 'selections').write_text(old)
        self.run_shell('. "$MODPATH/configure.sh"', before='prepare_targets() { return 1; }', success=False)
        self.assertEqual((self.active / 'selections').read_text(), old)

    @unittest.skipUnless(GOOGLE, 'Degoogler mode selection')
    def test_cancel_preserves_legacy_choice_and_marker(self):
        self.state.mkdir()
        (self.state / 'choice').write_text('B\n')
        (self.state / 'uninstall_updates').write_text('com.google.android.gms\n')
        before = {p.name: p.read_bytes() for p in self.state.iterdir()}
        self.install(success=False)
        self.assertEqual({p.name: p.read_bytes() for p in self.state.iterdir()}, before)

    @unittest.skipUnless(GOOGLE, 'Degoogler mode selection')
    def test_cancel_full_confirmation_preserves_state(self):
        self.install(['down', 'up', 'none'], success=False)
        self.assertFalse(self.state.exists())

    @unittest.skipUnless(GOOGLE, 'Degoogler mode selection')
    def test_mode_c_keeps_google(self):
        self.install(['down', 'down', 'up', 'down', 'down'])
        self.assertEqual(self.selections()['choice'], 'C')
        self.assertEqual(len(self.selected()), 3)

    @unittest.skipUnless(GOOGLE, 'Degoogler optional groups')
    def test_optional_intelligence_auto_and_launcher_preservation(self):
        self.install(['up', 'up', 'up'])
        self.assertEqual(len(self.selected()), 6)
        self.assertNotIn('com.google.android.gms', self.selected())
        paths = (self.stage / 'selected-targets').read_text()
        self.assertNotIn('SearchLauncher', paths)
        self.assertNotIn('qsb_at_bottom', paths)

    @unittest.skipUnless(GOOGLE, 'Degoogler microG upgrade')
    def test_full_upgrade_keeps_microg_replacement(self):
        self.active.mkdir()
        (self.active / 'selections').write_text('choice=B\nintelligence=yes\nauto=yes\n')
        self.observe('com.google.android.gms', signer='a' * 64)
        self.install()
        self.run_shell('cleanup_targets')
        self.assertFalse((self.work / 'pm-calls').exists())
        self.assertIn('state=present', (self.probes / 'com.google.android.gms').read_text())

    def test_uninstall_preserves_backups(self):
        backup = self.state / 'backups' / 'saved'
        backup.mkdir(parents=True)
        (backup / '0.apk').write_bytes(b'backup')
        script = (ROOT / 'uninstall.sh').read_text()
        script = script.replace('WL=/data/adb/cyberspacevii/' + ROOT.name, 'WL="$TEST/state"')
        script = script.replace('/data/adb/cyberspacevii', '"$TEST/parent"')
        result = subprocess.run(['sh', '-c', script], env={**os.environ, 'TEST': str(self.work)}, capture_output=True)
        self.assertTrue((backup / '0.apk').exists(), result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
