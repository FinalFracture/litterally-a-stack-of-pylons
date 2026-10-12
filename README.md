# Literally Just a Stack of Pylons

You are a traffic cone. Grab more cones, stack them, steer traffic.
Godot 4.7 (GDScript), Jolt physics.

## Run it

- **Editor:** open `project.godot` in Godot 4.7 and press **F5** (main scene: `scenes/twin_falls.tscn`).
- **Command line:** `godot --path .` from the repo root.
  Add test flags after `--`, e.g. `godot --path . -- --seed=7 --max-fps=45`.

Each run prints one line like this at boot:

```
PYLONS_LAUNCH seed=20261008 (default) spawn=250.239,0.350,247.594 (sidewalk) max_fps=0 keymouse=off logs=off | replay: godot --path . -- --seed=20261008 --spawn=250.239,0.350,247.594 --max-fps=0
```

Paste the `replay:` part into a bug report. It reproduces the same city and spawn point.

## Controls

| Action | Key |
|---|---|
| slide | W A S D or arrow keys |
| look | mouse |
| hop | Space |
| add a cone or stack to the top of your stack | left click (facing it, within about 1.2 m) |
| drop one cone | right click |
| swap (move into the cone you are looking at) | Shift |
| take top cone (drop it and take control of it) | E |
| pause | Esc |
| controls card | F1 |
| dev console | ~ |

Landing on top of a cone stack takes its top cone and puts it under your own stack.
F and X are kept free for mission accept and decline. Q and R are no longer bound.

## Test flags

Each flag can be an environment variable or a user argument after `--`. The argument wins.

| Env var | Argument | Effect |
|---|---|---|
| `PYLONS_SEED=N` | `--seed=N` | World seed. Default `20261008` (fixed). Same seed, same city. |
| `PYLONS_SPAWN=x,y,z` | `--spawn=x,y,z` | Spawn point in metres. Default: the sidewalk nearest the centre of chunk (0,0). |
| `PYLONS_MAX_FPS=N` | `--max-fps=N` | Sets `Engine.max_fps` (0 = uncapped). Try 60, 45, 30. |
| `PYLONS_KEYMOUSE=1` | `--keymouse` | Keyboard stand-in for the mouse: look with J L I K, take (left click) with U, drop (right click) with O. Off by default. |
| `PYLONS_LOGS=1` | `--logs` | Turns on telemetry prints and the traffic log files (written to `../logs/` next to the project folder). Off by default. |
| `PYLONS_FLEET=N` | | Number of traffic cars (default 36). |
| `PYLONS_FLEET_SEC=N` | | Fleet harness: logs traffic for N seconds, then quits. |

Windows PowerShell examples:

```powershell
godot --path . -- --seed=7 --max-fps=30
$env:PYLONS_KEYMOUSE = "1"; godot --path .; Remove-Item Env:PYLONS_KEYMOUSE
```

## World

- One fixed seed builds the same city every run. Chunk content is seeded from the world seed plus the chunk's grid coordinates.
- Only the centre 500 m chunk (0,0) is built at startup. There is no ring around it and no streaming yet.
- World cones are real rigid bodies: about 1.4 kg per standard cone (0.9 kg for a mini), with a heavy base and a low centre of mass. They start asleep. Cars hit them at bumper height, so a hit tips a cone over.

## Sounds

`scripts/sfx.gd` maps the names `click`, `knock`, `thunk` and `dull_click` to files in `Sounds_Music/sfx/`.
All four use the Asset Manager's CC0 set (`sfx_*.ogg`, several variants per slot, played through an `AudioStreamRandomizer`); `thunk` is the "cone impact on hard ground" set. Sources and licences: `Sounds_Music/sfx/CREDITS.md`. To swap a sound, change its file list in `SOUNDS`.
