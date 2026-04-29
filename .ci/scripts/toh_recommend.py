#!/usr/bin/env python3
import json
import sys
import textwrap
import argparse
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


TOH_JSON_URLS = [
    "https://openwrt.org/toh.json",
    "https://toh.openwrt.org/toh.json",
]

DEVICEPAGE_PREFIX = "https://openwrt.org/"
HWDATA_PREFIX = "https://openwrt.org/toh/hwdata/"


FILTERS = {
    "rammb": 512,
    "cpucores": 2,
    "cpumhz": 1300,
    "wlan50ghz_contains": "ax",
    "supportedcurrentrel_contains": "2",
}


OUTPUT_COLUMNS = [
    ("brand", "Brand"),
    ("model", "Model"),
    ("cpu", "CPU"),
    ("rammb", "RAM"),
    ("usbports", "USB"),
    ("cpucores", "Cores"),
    ("cpumhz", "MHz"),
    ("devicetype", "Type"),
    ("comments", "Comments"),
    ("installationmethods", "Install"),
    ("VIRT_hwdata", "HwData"),
]


def fetch_json(url: str) -> dict:
    req_headers = {
        "User-Agent": "Mozilla/5.0 (compatible; toh-recommend-script/1.0)",
        "Accept": "application/json,text/plain,*/*",
    }
    request = __import__("urllib.request", fromlist=["Request"]).Request(url, headers=req_headers)
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def fetch_first_available_json(urls: list[str]) -> tuple[dict, str]:
    last_error: Exception | None = None
    for url in urls:
        try:
            return fetch_json(url), url
        except Exception as exc:
            last_error = exc
    assert last_error is not None
    raise last_error


def value_to_string(value) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return ", ".join(str(item) for item in value if item not in (None, ""))
    return str(value)


def build_devicepage_url(value) -> str:
    text = value_to_string(value).strip()
    if not text:
        return ""
    if text.startswith("http://") or text.startswith("https://"):
        return text
    if text.startswith("toh:"):
        text = text.replace(":", "/")
    return DEVICEPAGE_PREFIX + text.lstrip("/")


def build_hwdata_url(device: dict) -> str:
    hwdata = value_to_string(device.get("VIRT_hwdata")).strip()
    if hwdata:
        if hwdata.startswith("http://") or hwdata.startswith("https://"):
            return hwdata

    device_id = value_to_string(device.get("deviceid")).strip()
    if not device_id or ":" not in device_id:
        return ""

    brand, model = device_id.split(":", 1)
    return HWDATA_PREFIX + brand + "/" + model


def get_output_value(device: dict, key: str) -> str:
    if key == "VIRT_hwdata":
        return build_hwdata_url(device)
    return value_to_string(device.get(key))


def get_markdown_output_value(device: dict, key: str) -> str:
    if key == "VIRT_hwdata":
        hw_url = build_hwdata_url(device)
        device_url = build_devicepage_url(device.get("devicepage"))
        parts = []
        if hw_url:
            parts.append(f"[HW]({hw_url})")
        if device_url:
            parts.append(f"[Device]({device_url})")
        return ", ".join(parts)
    return value_to_string(device.get(key))


def value_to_int(value) -> int | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value).strip()
    if not text:
        return None
    digits = "".join(ch for ch in text if ch.isdigit())
    return int(digits) if digits else None


def matches_filters(device: dict) -> bool:
    ram = value_to_int(device.get("rammb"))
    cores = value_to_int(device.get("cpucores"))
    mhz = value_to_int(device.get("cpumhz"))
    wifi5 = value_to_string(device.get("wlan50ghz")).lower()
    current_release = value_to_string(device.get("supportedcurrentrel")).lower()

    return (
        ram is not None
        and ram >= FILTERS["rammb"]
        and cores is not None
        and cores >= FILTERS["cpucores"]
        and mhz is not None
        and mhz >= FILTERS["cpumhz"]
        and FILTERS["wlan50ghz_contains"] in wifi5
        and FILTERS["supportedcurrentrel_contains"] in current_release
    )


def build_devices(payload: dict) -> list[dict]:
    columns = payload["columns"]
    devices = []
    for entry in payload["entries"]:
        device = dict(zip(columns, entry))
        if matches_filters(device):
            devices.append(device)
    devices.sort(key=lambda d: (value_to_string(d.get("brand")), value_to_string(d.get("model"))))
    return devices


def wrap_cell(text: str, width: int) -> list[str]:
    if not text:
        return [""]
    return textwrap.wrap(text, width=width, break_long_words=True, break_on_hyphens=False) or [""]


def print_table(devices: list[dict]) -> None:
    rows = []
    for device in devices:
        rows.append([get_output_value(device, key) for key, _title in OUTPUT_COLUMNS])

    headers = [title for _key, title in OUTPUT_COLUMNS]
    widths = []
    max_widths = {
        "Brand": 18,
        "Model": 24,
        "CPU": 12,
        "USB": 12,
        "RAM": 8,
        "Cores": 8,
        "MHz": 8,
        "5GHz": 16,
        "C.Release": 12,
        "Type": 24,
        "HwData": 30,
        "Comments": 80,
    }

    for index, header in enumerate(headers):
        content_width = max([len(header), *[len(row[index]) for row in rows]], default=len(header))
        widths.append(min(content_width, max_widths[header]))

    def sep() -> str:
        return "+-" + "-+-".join("-" * width for width in widths) + "-+"

    print(sep())
    print("| " + " | ".join(header.ljust(widths[i]) for i, header in enumerate(headers)) + " |")
    print(sep())

    for row in rows:
        wrapped_columns = [wrap_cell(row[i], widths[i]) for i in range(len(row))]
        height = max(len(lines) for lines in wrapped_columns)
        for line_index in range(height):
            rendered = []
            for col_index, lines in enumerate(wrapped_columns):
                value = lines[line_index] if line_index < len(lines) else ""
                rendered.append(value.ljust(widths[col_index]))
            print("| " + " | ".join(rendered) + " |")
        print(sep())


def escape_markdown_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", "<br>")


def print_markdown_table(devices: list[dict]) -> None:
    headers = [title for _key, title in OUTPUT_COLUMNS]
    print("| " + " | ".join(headers) + " |")
    print("| " + " | ".join("---" for _ in headers) + " |")

    for device in devices:
        row = [escape_markdown_cell(get_markdown_output_value(device, key)) for key, _title in OUTPUT_COLUMNS]
        print("| " + " | ".join(row) + " |")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch and filter OpenWrt TOH devices")
    parser.add_argument(
        "--format",
        choices=["text", "markdown"],
        default="text",
        help="output format",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        payload, source_url = fetch_first_available_json(TOH_JSON_URLS)
    except HTTPError as exc:
        print(f"HTTP error fetching TOH data: {exc.code} {exc.reason}", file=sys.stderr)
        return 1
    except URLError as exc:
        print(f"Network error fetching TOH data: {exc.reason}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"Unexpected error fetching TOH data: {exc}", file=sys.stderr)
        return 1

    devices = build_devices(payload)
    print(f"Source: {source_url}")
    print(
        "Filters: "
        f"RAM >= {FILTERS['rammb']}, "
        f"Cores >= {FILTERS['cpucores']}, "
        f"MHz >= {FILTERS['cpumhz']}, "
        f"5GHz contains '{FILTERS['wlan50ghz_contains']}', "
        f"C.Release contains '{FILTERS['supportedcurrentrel_contains']}'"
    )
    print(f"Matches: {len(devices)}")

    if not devices:
        return 0

    if args.format == "markdown":
        print_markdown_table(devices)
    else:
        print_table(devices)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
