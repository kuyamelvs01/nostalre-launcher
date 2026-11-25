#!/usr/bin/env bash
# The game folder Ragnarok Offline was pointed at, as one JSON object on stdout.
# The app stores that choice in client.json (data_grf, and the optional rdata,
# official_data and BGM paths, which need not sit next to data.grf).
# RAGNAROK_OFFLINE_HOME overrides the data folder (the same variable the app uses).
# Usage: scripts/ragnarok-offline-data.sh
set -euo pipefail

python3 -I - <<'PY'
import json, os, sys

def candidates():
    home = os.environ.get("RAGNAROK_OFFLINE_HOME")
    if home:
        yield os.path.join(home, "client.json")
        return
    if sys.platform == "darwin":
        yield os.path.expanduser("~/Library/Application Support/Ragnarok Offline/client.json")
    elif sys.platform == "win32":
        appdata = os.environ.get("APPDATA") or os.path.expanduser("~/AppData/Roaming")
        yield os.path.join(appdata, "Ragnarok Offline", "client.json")
    else:
        base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        yield os.path.join(base, "Ragnarok Offline", "client.json")

found = None
for path in candidates():
    if os.path.isfile(path):
        found = path
        break
if not found:
    sys.exit("Ragnarok Offline has no client.json on this machine. Open the app once and choose the folder that holds data.grf, or set RAGNAROK_OFFLINE_HOME to its data folder.")

with open(found, encoding="utf-8") as fh:
    client = json.load(fh)
data_grf = client.get("data_grf") or ""
if not data_grf or not os.path.isfile(data_grf):
    sys.exit(f"{found} does not name a data.grf that is there ({data_grf or 'unset'}). Choose the client folder again in Ragnarok Offline.")

def optional(key):
    value = client.get(key) or ""
    return value if value and os.path.exists(value) else ""

print(json.dumps({
    "dir": os.path.dirname(os.path.abspath(data_grf)),
    "data_grf": os.path.abspath(data_grf),
    "rdata_grf": optional("rdata_grf"),
    "official_grf": optional("official_grf"),
    "bgm_dir": optional("bgm_dir"),
}))
PY
