# Celestial TCG

A space-themed collectible card game for Roblox: build a deck around a Commander and a Celestial, battle friends or the practice bot, and open booster packs.

## Layout
- `build/` — every game script, one file each, named `Service.ScriptName.lua` (the source of truth)
- `test/` — the offline test suite (a Roblox mock running the real scripts) and balance simulators
- `tools/make_rbxmx.py` — packs `build/` into `.rbxmx` files to import into Roblox Studio

## Updating the game
1. `python3 tools/make_rbxmx.py build <output folder>`
2. In Studio, import the `.rbxmx` files (ReplicatedStorage, ServerScriptService, StarterPlayerScripts, ReplicatedFirst), replacing the old scripts
3. Test in Studio, then publish

## Tests
`python3 test/run_all.py`, `test/launch_test.py`, `test/economy_test.py`, `test/run_spectate.py`, `test/anomaly_test.py` (needs `pip install lupa`)

Player saves live in the `PlayerData_v2` data store. Never rename it: that would reset everyone's cards and purchases.

## Replays for videos (Studio only)
`python3 tools/replays.py 250` simulates games per scenario (featured cards, close
finishes) and writes `build/ServerScriptService.ReplayLibrary.lua`. In Studio, the
"Replays" button (top right) plays one on the real battle screen with clean footage;
Space pauses, Right steps, [ ] change speed, H shows the rest of the UI.
`python3 test/replay_test.py` checks every replay plays back exactly.
