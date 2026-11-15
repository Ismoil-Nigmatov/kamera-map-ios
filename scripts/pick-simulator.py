import json
import re
import subprocess
import sys

listing = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))


def runtime_version(runtime: str) -> tuple[int, ...]:
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return tuple(int(part) for part in match.groups()) if match else (0, 0)


candidates = []
for runtime, devices in listing["devices"].items():
    if ".iOS-" not in runtime:
        continue
    for device in devices:
        name = device["name"]
        if not name.startswith("iPhone") or "SE" in name:
            continue
        preference = 0 if re.fullmatch(r"iPhone \d+ Pro", name) else 1 if re.fullmatch(r"iPhone \d+", name) else 2
        number = re.search(r"\d+", name)
        candidates.append((runtime_version(runtime), -preference, int(number.group()) if number else 0, device["udid"], name))

if not candidates:
    sys.exit("no iPhone simulator available")

best = max(candidates)
print(best[3])
print(f"picked {best[4]} on iOS {'.'.join(map(str, best[0]))}", file=sys.stderr)
