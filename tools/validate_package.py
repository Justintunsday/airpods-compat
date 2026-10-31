#!/usr/bin/env python3
"""Read .deb ar/tar members without dpkg; validate scheme, paths and binaries."""
import argparse
import io
from pathlib import Path, PurePosixPath
import struct
import tarfile


def ar_members(data):
    assert data.startswith(b'!<arch>\n'), 'not a deb/ar archive'
    offset = 8
    while offset < len(data):
        header = data[offset:offset + 60]
        assert len(header) == 60 and header[58:] == b'`\n', 'invalid ar member'
        size = int(header[48:58])
        name = header[:16].decode().strip().rstrip('/')
        offset += 60
        payload = data[offset:offset + size]
        assert len(payload) == size, 'truncated ar member'
        yield name, payload
        offset += size + size % 2


def validate(path, scheme):
    members = dict(ar_members(Path(path).read_bytes()))
    assert members.get('debian-binary') == b'2.0\n'
    control_name = next(name for name in members if name.startswith('control.tar'))
    data_name = next(name for name in members if name.startswith('data.tar'))
    with tarfile.open(fileobj=io.BytesIO(members[control_name]), mode='r:*') as archive:
        entry = next(item for item in archive if item.name.lstrip('./') == 'control')
        text = archive.extractfile(entry).read().decode()
    fields = dict(line.split(': ', 1) for line in text.splitlines() if ': ' in line and not line.startswith(' '))
    expected = 'iphoneos-arm64' if scheme == 'rootless' else 'iphoneos-arm'
    assert fields['Architecture'] == expected, fields
    prefix = 'var/jb/' if scheme == 'rootless' else ''
    required = {
        prefix + 'Library/MobileSubstrate/DynamicLibraries/AirPodsCompat.dylib',
        prefix + 'Library/MobileSubstrate/DynamicLibraries/AirPodsCompatResources.dylib',
        prefix + 'Library/MobileSubstrate/DynamicLibraries/AirPodsCompat.plist',
        prefix + 'Library/MobileSubstrate/DynamicLibraries/AirPodsCompatResources.plist',
        prefix + 'Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist',
        prefix + 'usr/bin/acprefs'
    }
    with tarfile.open(fileobj=io.BytesIO(members[data_name]), mode='r:*') as archive:
        files = {}
        for item in archive:
            assert '..' not in PurePosixPath(item.name).parts and not item.name.startswith('/'), item.name
            name = item.name.removeprefix('./').rstrip('/')
            if not name or item.isdir(): continue
            assert not item.issym() and not item.islnk(), 'unexpected package link'
            if scheme == 'rootless': assert name.startswith(prefix), name
            else: assert not name.startswith('var/jb/'), name
            files[name] = item
        assert required <= files.keys(), required - files.keys()
        for name in required:
            if name.endswith('.dylib') or name.endswith('/acprefs'):
                item = files[name]
                assert item.mode & 0o111, f'not executable: {name}'
                binary = archive.extractfile(item).read()
                assert binary[:4] == b'\xca\xfe\xba\xbe', f'not universal Mach-O: {name}'
                count = struct.unpack_from('>I', binary, 4)[0]
                arches = [struct.unpack_from('>II', binary, 8 + i * 20) for i in range(count)]
                assert {(cpu, sub & 0xff) for cpu, sub in arches} >= {(0x100000c, 0), (0x100000c, 2)}, arches
    print(f'PASS {Path(path).name}: {expected}, install prefix, required files and arm64/arm64e')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package')
    parser.add_argument('--scheme', choices=['rootless', 'rootful'], required=True)
    options = parser.parse_args()
    validate(options.package, options.scheme)
