#!/usr/bin/env bash
# Desktop trial of nostalre-client (native Rust/wgpu RO client) against our servers, built for its packet
# version. Builds the servers and a database (account tester/tester, GM) on first use, points the client's
# config.json at the game files (game-data/, or the folder Ragnarok Offline saved) and the local login
# server, then runs both. Quitting the client stops the servers it
# started; servers already running for that version are used as they are.
# The client speaks one packet version (PACKETVER, common.sh) to a Renewal server.
# Needs: nostalre-client checked out (the client is built incrementally before each run).
# Usage: scripts/run-nostalre.sh   (NOSTALRE_DIR=<checkout>, default client/;
#   GAME_DATA=<folder with data.grf>, default game-data/, or the folder Ragnarok Offline
#   already points at when game-data/ has no data.grf (scripts/ragnarok-offline-data.sh);
#   NOSTALRE_TRACE=0 to trace only unhandled packets;
#   NOSTALRE_SCRIPT=<file> NOSTALRE_CHAR_ID=<id>: log in as tester, enter that character and run the script,
#   see scripts/run-nostalre-script.sh)
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Game files: game-data/ when it has data.grf, otherwise the client folder saved by Ragnarok Offline.
game_data="$GAME_DATA"
ro_json=""
if [ ! -f "$game_data/data.grf" ]; then
	ro_json="$("$ROOT/scripts/ragnarok-offline-data.sh")"
	game_data="$(python3 -I -c 'import json,sys; print(json.loads(sys.argv[1])["dir"])' "$ro_json")"
	echo "game files from Ragnarok Offline: $game_data"
fi

client="$CLIENT"
client_info="$(native_client_info "$client")"
mapfile -t client_parts <<< "$client_info"
exe="${client_parts[2]}"
# always build: a no-op when nothing changed, and a run never shows a client older than the code
( cd "$client" && cargo build -q --release --bin "${exe##*/}" )
[ -x "$OUT/host/bin/map-server" ] || "$ROOT/scripts/build-server.sh" host
[ -f "$OUT/db/ragnarok.db" ] || "$ROOT/scripts/make-db.sh" --test-account

# GRFs in DATA.INI order (data.grf alone without one), then official_data.grf when it is there and DATA.INI does not
# name it, as the Android app does (GameDir.archives); the client's first archive wins too, game-data/data over
# them; everything else the client keeps as it wrote it
python3 -I - "$client" "$game_data" "$OUT" "$ROOT" "$ro_json" <<'EOF'
import configparser, json, os, shutil, sys
client, data, out, root, ro_raw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
ro = json.loads(ro_raw) if ro_raw else {}
path = os.path.join(client, "config.json")
sample = os.path.join(client, "config.sample.json")
config = json.load(open(path if os.path.exists(path) else sample))
ini = configparser.ConfigParser()
ini.read(os.path.join(data, "DATA.INI"))
listed = [(k, v) for k, v in ini["Data"].items() if k.isdigit()] if ini.has_section("Data") else []
names = [name for _, name in sorted(listed, key=lambda kv: int(kv[0]))]
names = names or ["data.grf"]
grf_paths = [os.path.join(data, name) for name in names]
seen = {os.path.normcase(os.path.abspath(p)) for p in grf_paths}
extras = [ro.get("rdata_grf") or "", ro.get("official_grf") or "", os.path.join(data, "official_data.grf")]
for extra in extras:
    if not extra or not os.path.isfile(extra):
        continue
    key = os.path.normcase(os.path.abspath(extra))
    if key in seen:
        continue
    # DATA.INI already named official_data.grf by its file name: do not add the copy beside data.grf twice
    if os.path.basename(extra).lower() in (n.lower() for n in names) and os.path.dirname(os.path.abspath(extra)) == os.path.abspath(data):
        continue
    grf_paths.append(extra)
    seen.add(key)
config["grf_paths"] = grf_paths
config["bgm_path"] = ro.get("bgm_dir") or os.path.join(data, "BGM")
# the pinned client's folder, the first archive's: its System and SystemEN tables (map titles, special pop-ups)
config["install_dir"] = os.path.dirname(os.path.normpath(config["grf_paths"][0])) if config["grf_paths"] else None
# loose files over the GRFs, as the Android app gives them (LooseFiles): game-data/data first, then the English
# text (english/: nostalre-english import ... game-data/english/data) under it.
# Their names are CP949 bytes spelled as Latin-1 (grf-server's convention); the client wants the Korean
# itself, so it reads a mirror of symlinks under decoded names, rebuilt each run so removed files go too.
# english text imported into this repo still applies when the GRFs come from Ragnarok Offline
layers = []
for loose in (os.path.join(data, "data"), os.path.join(data, "english", "data"), os.path.join(root, "game-data", "english", "data")):
    if os.path.isdir(loose) and loose not in layers:
        layers.append(loose)
mirror = os.path.join(out, "nostalre-data")
shutil.rmtree(mirror, ignore_errors=True)
for loose in layers:
    for walk_root, _, files in os.walk(loose):
        for name in files:
            source = os.path.join(walk_root, name)
            rel = os.path.relpath(source, loose)
            try:
                rel = rel.encode("latin-1").decode("cp949")
            except (UnicodeEncodeError, UnicodeDecodeError):
                pass  # already plain or real Unicode
            link = os.path.join(mirror, rel)
            if os.path.lexists(link):
                continue  # an earlier layer has it
            os.makedirs(os.path.dirname(link), exist_ok=True)
            os.symlink(source, link)
config["data_dir"] = mirror if layers else None
config["login_servers"] = [{"name": "nostalRE", "host": "127.0.0.1", "port": 6900}]
# a scripted run logs in and enters its character by itself (the hub's solo launch)
char_id = os.environ.get("NOSTALRE_CHAR_ID")
user, password = os.environ.get("NOSTALRE_USER", "tester"), os.environ.get("NOSTALRE_PASS", "tester")
config["solo"] = {"username": user, "password": password, "char_id": int(char_id)} if char_id else None
# every packet both ways goes to out/logs/nostalre-client.log, so a problem can be read back at once;
# NOSTALRE_TRACE=0 logs only the unhandled ones
trace = os.environ.get("NOSTALRE_TRACE") != "0"
config.setdefault("debug", {})["trace_packet"] = "all" if trace else "unhandled"
config["trace_packets_send"] = config["trace_packets_recv"] = trace
json.dump(config, open(path, "w"), indent=2)
EOF

logs="$OUT/logs"
# 6900 is also Ragnarok Offline's login port. That server speaks 20221005 (or 20250402);
# this client speaks PACKETVER and would be dropped. Only reuse a login port our map-server holds.
if ss -ltn | grep -q '127.0.0.1:6900 '; then
	if ! pgrep -x map-server >/dev/null 2>&1; then
		echo "127.0.0.1:6900 is already taken, and nostalRE's map-server is not listening." >&2
		echo "Quit Ragnarok Offline if it is open. Its server cannot log this client in:" >&2
		echo "nostalRE speaks packet version $PACKETVER; that app speaks 20221005 or 20250402." >&2
		echo "The game files still come from the folder that app points at. Characters for this client stay in out/db." >&2
		exit 1
	fi
	echo "servers already running: using them"
else
	rm -f "$logs/map.log" # the wait below must not find the last run's line
	"$ROOT/scripts/run-servers.sh" &
	servers=$!
	trap 'kill $servers 2>/dev/null; wait' EXIT INT TERM
	timeout 180 bash -c "until grep -aq 'Map-server connected to char-server' '$logs/map.log' 2>/dev/null; do sleep 1; done"
fi

# the client reads config.json from the working directory; NOSTALRE_LOG gives a second client its own log
( cd "$client" && "$exe" ) 2>&1 | tee "${NOSTALRE_LOG:-$logs/nostalre-client.log}"
