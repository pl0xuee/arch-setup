#!/usr/bin/env python3
"""Prepare NAS fstab entries and GTK folder bookmarks without mounting shares."""

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import time
from urllib.parse import unquote, urlsplit


def escape_field(value):
    return value.replace('\\', r'\134').replace(' ', r'\040').replace('\t', r'\011').replace('\n', r'\012')


def unescape_field(value):
    return re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), value)


def automount_options(options):
    # device-timeout applies to device units, not CIFS network sources.
    parts = [p for p in options.split(',') if p and p != 'x-gvfs-show'
             and not p.startswith('x-systemd.device-timeout=')]
    for required in ('_netdev', 'nofail', 'x-systemd.automount', 'x-gvfs-hide'):
        if required not in parts:
            parts.append(required)
    return ','.join(parts)


def render_fstab(text, source, mountpoint, credentials, defaults):
    if not mountpoint.startswith('/') or mountpoint == '/':
        raise ValueError('NAS mount point must be an absolute path below /')
    if ',' in credentials or not credentials.startswith('/'):
        raise ValueError('credentials must be an absolute path without commas')
    lines = text.splitlines(keepends=True)
    matches = []
    for i, line in enumerate(lines):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        fields = list(re.finditer(r'\S+', line))
        if len(fields) >= 2 and unescape_field(fields[1][0]) == mountpoint:
            matches.append((i, fields))
    if len(matches) > 1:
        raise ValueError(f'multiple fstab entries for {mountpoint}; left unchanged')
    if matches:
        i, fields = matches[0]
        if len(fields) < 4:
            raise ValueError(f'incomplete fstab entry for {mountpoint}; left unchanged')
        options = fields[3][0]
        managed = (unescape_field(fields[0][0]) == source and fields[2][0] == 'cifs'
                   and f'credentials={escape_field(credentials)}' in options.split(','))
        if not managed:
            raise ValueError(f'{mountpoint} belongs to another fstab entry; left unchanged')
        # Replace only the option field; retain comments, whitespace and all
        # permission, protocol and idle-timeout settings on an existing entry.
        lines[i] = (lines[i][:fields[3].start()] + automount_options(options)
                    + lines[i][fields[3].end():])
        return ''.join(lines)
    options = automount_options(f'credentials={escape_field(credentials)},{defaults}')
    sep = '\n' if text and not text.endswith('\n') else ''
    return text + sep + f'{escape_field(source)}\t{escape_field(mountpoint)}\tcifs\t{options}\t0 0\n'


def render_bookmarks(text, mountpoint, label):
    if not mountpoint.startswith('/'):
        raise ValueError('bookmark target must be absolute')
    target = os.path.normpath(mountpoint)
    for line in text.splitlines():
        fields = line.split(maxsplit=1)
        if not fields:
            continue
        uri = urlsplit(fields[0])
        if (uri.scheme == 'file' and uri.netloc in ('', 'localhost')
                and os.path.normpath(unquote(uri.path)) == target):
            return text  # Keep the user's existing label and position.
    uri = Path(target).as_uri()
    label = label.replace('\n', ' ').replace('\r', ' ')
    sep = '\n' if text and not text.endswith('\n') else ''
    return text + sep + f'{uri} {label}\n'


def write_if_changed(path, content, dry_run=False):
    path = Path(path).resolve()
    original = path.read_text() if path.exists() else ''
    if original == content:
        return False
    if dry_run:
        print(f'Would update {path}')
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    previous = path.stat() if path.exists() else None
    fd, temporary = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
            os.fchmod(output.fileno(), stat.S_IMODE(previous.st_mode) if previous else 0o644)
            if previous and (previous.st_uid, previous.st_gid) != (os.geteuid(), os.getegid()):
                os.fchown(output.fileno(), previous.st_uid, previous.st_gid)
        if previous:
            backup = path.with_name(f'{path.name}.bak-arch-setup-{time.time_ns()}')
            shutil.copy2(path, backup)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    fstab = sub.add_parser('fstab')
    for arg in ('path', 'source', 'mountpoint', 'credentials', 'defaults'):
        fstab.add_argument(arg)
    bookmarks = sub.add_parser('bookmark')
    for arg in ('path', 'mountpoint', 'label'):
        bookmarks.add_argument(arg)
    for command in (fstab, bookmarks):
        command.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    path = Path(args.path)
    try:
        text = path.read_text() if path.exists() else ''
        if args.command == 'fstab':
            content = render_fstab(text, args.source, args.mountpoint, args.credentials, args.defaults)
        else:
            content = render_bookmarks(text, args.mountpoint, args.label)
        changed = write_if_changed(path, content, args.dry_run)
        if not args.dry_run:
            print(f'{"Updated" if changed else "Already configured"}: {path}')
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
