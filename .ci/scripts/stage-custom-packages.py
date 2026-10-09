#!/usr/bin/env python3
"""Stage release APKs and pin the build to their embedded package versions."""
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile


def stage_apk(source, destination, apk, expected_name, expected_version=None):
    metadata = subprocess.check_output([str(apk), 'adbdump', str(source)], text=True)
    name = re.search(r'^  name: (\S+)$', metadata, re.M).group(1)
    version = re.search(r'^  version: (\S+)$', metadata, re.M).group(1)
    if name != expected_name:
        raise ValueError(f'Expected {expected_name}, got {name}')
    if expected_version and not re.fullmatch(re.escape(expected_version) + r'-r\d+', version):
        raise ValueError(f'{name}: expected {expected_version}, got {version}')
    (destination / f'{name}-{version}.apk').write_bytes(Path(source).read_bytes())
    return f'{name}={version}'


def download(url, destination):
    subprocess.run(['curl', '-fL', '--retry', '3', '--retry-delay', '2',
                    '-o', str(destination), url], check=True)


def main():
    device = Path(os.environ['DEVICE_DIR'])
    destination = Path('imagebuilder/packages')
    destination.mkdir(parents=True, exist_ok=True)
    apk = Path('imagebuilder/staging_dir/host/bin/apk').resolve()
    openwrt = os.environ['OPENWRT_VERSION']
    awg = os.environ['AMNEZIAWG_VERSION']
    if awg != f'v{openwrt}':
        raise ValueError('AMNEZIAWG_VERSION must match OPENWRT_VERSION (kernel ABI)')
    pins = {}
    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        for line in (device / 'apk-urls.txt.tpl').read_text().splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            name, url = line.split()
            url = re.sub(r'\$\{([A-Z_]+)\}', lambda m: os.environ[m[1]], url)
            source = work / 'download.apk'
            download(url, source)
            pins[name] = stage_apk(source, destination, apk, name)

        tag = os.environ['PUREWRT_VERSION']
        version = tag.removeprefix('v')
        arch = os.environ['OPKG_ARCH']
        branch = os.environ['OPENWRT_VERSION_MAJOR']
        archive = work / 'purewrt.tar.gz'
        download(f'https://github.com/mglants/purewrt/releases/download/{tag}/'
                 f'purewrt-{branch}-{arch}.tar.gz', archive)
        with tarfile.open(archive) as release:
            for name in ('purewrt', 'luci-app-purewrt'):
                matches = [m for m in release.getmembers() if m.isfile() and
                           re.fullmatch(re.escape(name + '-' + version) + r'-r\d+\.apk', Path(m.name).name)]
                if len(matches) != 1:
                    raise ValueError(f'Expected one {name} {version} APK, found {len(matches)}')
                source = work / 'download.apk'
                source.write_bytes(release.extractfile(matches[0]).read())
                pins[name] = stage_apk(source, destination, apk, name, version)

    packages = os.environ['PACKAGES'].split()
    packages = [pins.get(p.split('=')[0], p) for p in packages]
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write('PACKAGES=' + ' '.join(packages) + '\n')
    print('Staged and pinned: ' + ' '.join(pins.values()))


if __name__ == '__main__':
    main()
