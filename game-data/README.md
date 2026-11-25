# Game data

For playing nostalRE on the desktop (`scripts/run-nostalre.sh`), put your own game files here, laid out like the
Android app's game folder. They are not part of this repository and are never committed.

If this folder has no `data.grf`, the script uses the client folder already chosen in
[Ragnarok Offline](https://github.com/Flux159/ragnarokoffline.app): `data.grf`, and when set `rdata.grf`,
`official_data.grf` and `BGM`, from `client.json` in that app's data folder (`~/.local/share/Ragnarok Offline`
on Linux, or `RAGNAROK_OFFLINE_HOME`). nostalRE still starts its own servers. That app's login server is a
different packet version (20221005 or 20250402; nostalRE speaks 20250716), so quit Ragnarok Offline before
playing — both want port 6900, and this client cannot log into that server. Characters made there stay there;
this run keeps its own in `out/db`. `GAME_DATA` names a folder directly and skips the lookup.

What goes in, where it comes from and what is lost without each piece: see
[Prerequisites](../README.md#prerequisites) and [Installation](../README.md#installation) in the main README. In
short, the kRO 2025-07-16 client folder as it is ([WARP0716](https://github.com/CrazyBebop/WARP0716)'s WARPGATE
downloader fetches it), plus ROenglishRE's `official_data.grf` and the English text in its own folder:

```
game-data/
├── DATA.INI            optional: 1=data.grf, 2=official_data.grf
├── data.grf
├── official_data.grf
├── System/
├── SystemEN/
├── BGM/
├── data/               kRO's loose files (they win over the English text)
└── english/data/       the English text, written by the importer (see below)
```

The English text, from a ROenglishRE checkout (`english/` is the importer the Android app runs too):

```sh
cargo run --release --manifest-path english/Cargo.toml -- import <ROenglishRE checkout> server/db/re game-data/english/data
```
