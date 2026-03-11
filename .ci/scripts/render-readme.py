#!/usr/bin/env python3
import os
import re
from pathlib import Path
from jinja2 import Environment, FileSystemLoader, select_autoescape

repo_owner = os.environ.get("REPO_OWNER", os.environ.get("GITHUB_REPOSITORY_OWNER", ""))
repo_name = os.environ.get("REPO_NAME", os.environ.get("GITHUB_REPOSITORY", ""))  # "owner/repo"
default_branch = os.environ.get("DEFAULT_BRANCH", "main")

env = Environment(
    loader=FileSystemLoader(".ci/templates"),
    autoescape=select_autoescape()
)

# Parse KEY=VALUE lines from devices/<router>/env.sh
ENV_RE = re.compile(r'^\s*([A-Z0-9_]+)\s*=\s*(.+?)\s*$')

def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")

def read_first_nonempty_line(path: Path) -> str:
    for line in read_text(path).splitlines():
        s = line.strip()
        if s:
            return s
    return ""

def strip_quotes(value: str) -> str:
    v = value.strip()
    if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
        v = v[1:-1].strip()
    return v

def parse_env_file(env_sh_path: Path) -> dict[str, str]:
    """
    Reads a shell-style env file with lines like:
      KEY=value
      KEY="value"
    Ignores comments and blank lines. Does not execute shell.
    """
    if not env_sh_path.exists():
        return {}

    data: dict[str, str] = {}
    for line in read_text(env_sh_path).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        m = ENV_RE.match(line)
        if not m:
            continue

        key = m.group(1)
        raw = strip_quotes(m.group(2))
        data[key] = raw

    return data

def parse_packages(packages_path: Path) -> list[str]:
    if not packages_path.exists():
        return []
    pkgs: list[str] = []
    for line in read_text(packages_path).splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        pkgs.append(s)
    return pkgs

def github_blob_url(repo: str, branch: str, rel_path: str) -> str:
    return f"https://github.com/{repo}/blob/{branch}/{rel_path}"

def build_routers() -> list[dict]:
    routers: list[dict] = []
    devices_dir = Path("devices")
    firmwares_dir = Path("firmwares")

    if not devices_dir.exists():
        return routers

    for router_dir in sorted(
        [p for p in devices_dir.iterdir() if p.is_dir()],
        key=lambda p: p.name.lower()
    ):
        router_id = router_dir.name  # stable identifier from directory name

        packages_path = router_dir / "packages.txt"
        env_sh_path = router_dir / "env.sh"

        env_vars = parse_env_file(env_sh_path)

        router_name = env_vars.get("DEVICE_NAME", router_id)
        router_vendor = env_vars.get("DEVICE_VENDOR", "")
        openwrt_version = env_vars.get("OPENWRT_VERSION", "")

        packages = parse_packages(packages_path)
        comment = env_vars.get("DEVICE_COMMENT", "")

        routers.append({
            "id": router_id,
            "name": router_name,
            "vendor": router_vendor,
            "openwrt_version": openwrt_version,
            "packages": packages,
            "packages_count": len(packages),
            "comment": comment,

            # helpful file links in repo
            "packages_file_url": github_blob_url(repo_name, default_branch, f"devices/{router_id}/packages.txt"),
            "env_file_url": github_blob_url(repo_name, default_branch, f"devices/{router_id}/env.sh")
        })

    return routers

if __name__ == "__main__":
    routers = build_routers()
    template = env.get_template("README.md.j2")
    with open("./README.md", "w", encoding="utf-8") as f:
        f.write(template.render(
            repo_name=repo_name,
            repo_owner=repo_owner,
            routers=routers
        ))
