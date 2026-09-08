#!/usr/bin/env python3
"""NAS configuration tests; all file writes stay in temporary directories."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('nas_mounts', Path(__file__).resolve().parents[1] / 'lib/nas_mounts.py')
nas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nas)


class NasConfigurationTests(unittest.TestCase):
    def render(self, text, **kwargs):
        args = dict(source='//nas/More Storage', mountpoint='/mnt/MoreStorage',
                    credentials='/etc/samba/creds-nas',
                    defaults='uid=1001,gid=1002,file_mode=0664,dir_mode=0775,x-systemd.idle-timeout=60')
        args.update(kwargs)
        return nas.render_fstab(text, **args)

    def test_new_entry_and_rerun(self):
        original = '# Original configuration\nUUID=abc / ext4 defaults 0 1\n'
        result = self.render(original)
        self.assertTrue(result.startswith(original))
        self.assertIn(r'//nas/More\040Storage', result)
        for option in ('x-systemd.automount', 'x-gvfs-hide', '_netdev', 'nofail',
                       'x-systemd.idle-timeout=60', 'uid=1001', 'gid=1002'):
            self.assertIn(option, result)
        self.assertNotIn('x-gvfs-show', result)
        self.assertNotIn('device-timeout', result)
        self.assertEqual(result, self.render(result))

    def test_migrate_only_exact_managed_entry(self):
        unrelated = '//other/Share /mnt/Other cifs credentials=/etc/other,x-gvfs-show 0 0\n'
        original = (unrelated + '//nas/More\\040Storage  /mnt/MoreStorage\tcifs  '
                    'credentials=/etc/samba/creds-nas,uid=123,gid=456,vers=3.1.1,'
                    'file_mode=0600,x-gvfs-show,x-systemd.idle-timeout=120,'
                    'x-systemd.device-timeout=10  0 0 # keep comment\n')
        result = self.render(original)
        self.assertTrue(result.startswith(unrelated))
        managed = result.splitlines()[1]
        for preserved in ('uid=123', 'gid=456', 'vers=3.1.1', 'file_mode=0600',
                          'x-systemd.idle-timeout=120', '  0 0 # keep comment'):
            self.assertIn(preserved, managed)
        self.assertNotIn('device-timeout', managed)
        self.assertNotIn('x-gvfs-show', managed)
        self.assertEqual(result, self.render(result))

    def test_unrelated_mountpoint_conflict_is_rejected(self):
        for entry in ('//other/Share /mnt/MoreStorage cifs credentials=/etc/samba/creds-nas 0 0\n',
                      '//nas/More\\040Storage /mnt/MoreStorage cifs credentials=/etc/other 0 0\n',
                      '//nas/More\\040Storage /mnt/MoreStorage nfs defaults 0 0\n'):
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                self.render(entry)

    def test_duplicate_entries_are_rejected(self):
        result = self.render('')
        with self.assertRaises(ValueError):
            self.render(result + result)

    def test_mountpoint_is_matched_literally(self):
        original = '//other/Share /mnt/AB cifs defaults 0 0\n'
        result = self.render(original, mountpoint='/mnt/A[B]')
        self.assertTrue(result.startswith(original))
        self.assertIn('/mnt/A[B]', result)

    def test_escaping_and_mountpoint_validation(self):
        result = self.render('', mountpoint='/mnt/More Storage')
        self.assertIn(r'/mnt/More\040Storage', result)
        self.assertEqual(result, self.render(result, mountpoint='/mnt/More Storage'))
        for path in ('/', 'relative'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.render('', mountpoint=path)

    def test_bookmarks_preserve_labels_and_other_entries(self):
        original = 'file:///home/example/Documents My documents\nfile:///mnt/More%20Storage My NAS\n'
        self.assertEqual(original, nas.render_bookmarks(original, '/mnt/More Storage', 'More Storage'))
        result = nas.render_bookmarks(original, '/mnt/Backup', 'Backup')
        self.assertEqual(original + 'file:///mnt/Backup Backup\n', result)
        self.assertEqual(result, nas.render_bookmarks(result, '/mnt/Backup', 'New label'))

    def test_bookmarks_encode_paths_and_normalize_uri(self):
        result = nas.render_bookmarks('', '/mnt/More Storage/#1', 'Share')
        self.assertEqual('file:///mnt/More%20Storage/%231 Share\n', result)
        original = 'file://localhost/mnt/More%20Storage/ Custom label'
        self.assertEqual(original, nas.render_bookmarks(original, '/mnt/More Storage', 'Ignored'))

    def test_atomic_write_backup_permissions_and_idempotence(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fstab'
            path.write_text('# original\n'); path.chmod(0o640)
            result = self.render(path.read_text())
            self.assertTrue(nas.write_if_changed(path, result))
            backups = list(path.parent.glob('fstab.bak-arch-setup-*'))
            self.assertEqual(1, len(backups))
            self.assertEqual('# original\n', backups[0].read_text())
            self.assertEqual(0o640, path.stat().st_mode & 0o777)
            self.assertFalse(nas.write_if_changed(path, result))
            self.assertEqual(backups, list(path.parent.glob('fstab.bak-arch-setup-*')))

    def test_dry_run_creates_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'gtk-3.0/bookmarks'
            self.assertTrue(nas.write_if_changed(path, 'file:///mnt/Backup Backup\n', dry_run=True))
            self.assertEqual([], list(Path(folder).iterdir()))

    def test_bookmarks_belong_to_the_invoking_user(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'gtk-3.0/bookmarks'
            nas.write_if_changed(path, nas.render_bookmarks('', '/mnt/Backup', 'Backup'))
            self.assertEqual(os.getuid(), path.stat().st_uid)
            self.assertEqual(os.getgid(), path.stat().st_gid)


if __name__ == '__main__':
    unittest.main()
