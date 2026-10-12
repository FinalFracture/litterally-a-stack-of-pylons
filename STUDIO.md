# Literally a Stack of Pylons — Studio Playbook (Windows / Godot 4)

Use this as the frozen production bible. Do not re-paste the original 16-section brief into every chat.

## 0. Verdict

Grok is useful. A single mega-prompt is not.

- One 4k–8k word "build the whole game" message burns context on city tiles, traffic AI, and dialogue philosophy before a cone can slide.
- A fake "8-person team" in one thread also burns tokens: every role re-reads the same spec.
- The professional pattern is **one frozen bible + one active implementer + short specialist reviews**.
- You are Producer. Grok is a contract studio. Godot on your Windows machine is the only runtime that matters.

You still want a team. Run the team **sequentially**, not as eight simultaneous personalities in one context window.

## 1. Install first (do this before any build prompt)

On the Windows machine that will press F5:

1. Install **Godot 4.4.1 or newer 4.x stable** (standard build, not .NET). Brief says 4.3+; current supported line is 4.5–4.7. Stay on one version for the whole project.
2. Create an empty folder: `C:\dev\literally_a_stack_of_pylons`
3. In Godot: New Project → that folder → Renderer **Forward Plus** first. If a mid-range PC stutters, switch project to **Compatibility** later. Do not debate this in chat.
4. Enable Git immediately.
5. Put this playbook in the repo as `STUDIO.md`.
6. Never ask Grok to "create the Godot editor project from nothing and also invent meshes and a city" in message 1.

Acceptance of this step: Godot opens, empty 3D scene, F5 shows a grey viewport.

## 2. Token law

| Do | Do not |
| --- | --- |
| One slice per conversation or per compact prompt | Paste the full brief every time |
| Paste only the relevant slice spec + file list + last error | Ask for art direction essays mid-physics |
| After each slice: F5, 30-second playtest, paste errors | Let the model keep generating after it claims "done" |
| Freeze constants in `game_constants.gd` once | Re-derive 18" → meters in every prompt |
| City last | Buildings first |
| Primitive CSG / CylinderMesh | Custom sculpted cone art |
| Kill a feature if FPS or joints explode | "Just add the van pickup animation" |

Soft budget per slice: one implementation pass + one fix pass. If the second fix pass still fails, change approach (see physics fork below), do not keep patching.

## 3. Team (roles you actually need)

Hire roles as **prompt hats**, not as standing characters.

| Role | When they speak | What they are allowed to output |
| --- | --- | --- |
| Producer (you) | Every slice | Playtest notes, "ship / cut / defer", F5 results |
| Software Director | Once, up front | Architecture decision record. Then silent unless a system is redesigned |
| Gameplay Programmer | Every build slice | GDScript + scene structure + "how to F5" |
| Technical Director | After first 10-cone stack and after city tiles | Perf budget, collider policy, streaming |
| Art Director | Once, 20 lines, then only asset lists | Palette, primitive kit, no faces, no hero cone |
| Story Director | Once, 15 lines | Silent-box trigger flags only. No jokes, no strings |
| QA | After each slice | Acceptance checklist, repro steps |

Cut from the payroll until V0 ships: narrative designer, composer, multiplayer engineer, UX novelist, systems designer for RPG junk the brief already banned.

Story Director is almost unemployed on purpose. That is correct.

### Role prompts (copy, do not expand)

**Software Director — run once**

```
You are Software Director only. Do not write game code.
Game: Godot 4.x, GDScript, Windows, "literally a stack of pylons".
Decide and freeze:
1. Possessed locomotion: CharacterBody3D vs RigidBody3D vs hybrid.
2. Stack representation: parented visuals vs compound collider vs per-piece RigidBody + joints.
3. How drop-bottom and mid-stack soul-swap map onto that representation.
4. File/scene list for slices 1–8 only (no city).
5. What V0 is allowed to fake.
Output: a one-page ADR. No prose about tone.
```

**Art Director — run once**

```
You are Art Director only. 20 lines max.
Palette: orange PVC, white stripe, grey city, sodium night work lights.
No faces, no names, no arms. Title is exact lowercase: literally a stack of pylons.
Specify primitive mesh recipe for standard cone, mini, barrel (Godot CylinderMesh / CSG only).
List decal flags for silent portraits: bent, tire stamp, dirt, tape, glasses mesh.
Do not request custom sculpted assets.
```

**Story Director — run once**

```
You are Story Director only. 15 lines max.
No spoken jokes. No subtitle file. No NPC names.
Define only trigger → portrait-flag mappings:
- hard car hit
- first successful stack
- soul swap
- respawn after fall
Tone: deadpan civic training video. Living plastic never uses words.
World signs may say DETOUR / WET CEMENT.
```

**Gameplay Programmer — every slice**

```
You are Gameplay Programmer for Godot 4 GDScript.
Follow STUDIO.md slice N. Do not redesign architecture.
Do not generate city tiles. Do not invent RPG systems.
Output only the files for this slice. After code, list exact F5 steps and a 5-line playtest script.
If a requirement fights the current architecture, say so in 3 lines and propose the cheapest patch.
```

**QA — after each slice**

```
You are QA. I pasted playtest notes and errors.
Map them to STUDIO.md acceptance for slice N.
Return: pass/fail per criterion, one repro, one cheapest fix. No new features.
```

## 4. Architecture freeze (do not re-litigate in chat)

This is the expensive part of the original brief. Lock it.

### V0 physics (ship this)

Hybrid, two phases:

**Phase A — playable stack (slices 1–5, 8)**  
Possessed body is one `CharacterBody3D` named `SoulBody`.  
Child pieces are `Node3D` meshes parented in a column.  
Slide = `velocity` on XZ, no walk cycle, slight squash.  
Jump = single `velocity.y` impulse, mass/height scaled.  
Stack = reparent target onto top socket if upright and cap allows.  
Drop Q = detach bottom child, spawn a free `RigidBody3D` clone at that pose, remaining children shift down via physics-assist lerp (not a teleport explosion).  
Swap E = deposit current column as free rigid pieces or one rigid column, possess target.

Why: toy movement stays readable; you get a game in a few slices; 22-high columns will not explode the solver before you have drop/swap.

**Phase B — breakable civic physics (slices 4b, 12)**  
Each free piece is `RigidBody3D`.  
A possessed stack can stay kinematic until an impulse above threshold converts it to a jointed column.  
Joints: `Generic6DOFJoint3D` or stiff slider + angular limits along local Y.  
Break = joint impulse exceeds per-joint threshold; chunks that remain connected stay parented; soul stays with anchor piece + anything still joined above it.

Do not start with 22 live rigid bodies plus cars. That is how V0 dies in the solver.

### Constants (author once)

```
STANDARD_H        = 0.4572
STANDARD_EXTRA    = 0.1524
MINI_H            = 0.3048
MINI_EXTRA        = 0.1016
BARREL_H          = 1.0
BARREL_EXTRA      = 0.38
CAP_M             = 3.6576
BASE_R            = 0.14
UPRIGHT_DOT       = cos(radians(28))
SWAP_RANGE        = 1.6
```

Height of a stack is `base_piece.height + sum(extra of every piece above base)`, not `count * height`. Cap is meters, never "22 cones" except as a standard-only sanity check.

### Soul rules (non-negotiable)

- Soul = entire possessed column, not a marked segment.
- Q drops **bottom piece only**. Height 1 = no-op + dull click.
- After Q, remaining column settles; do not teleport onto ground.
- E deposits current column, then possesses target + everything above target.
- After a shatter, soul anchor = last inhabited piece + still-joined pieces above it.
- No "right cone" button.

### Camera

Third person, boom length = `2.4 + 0.55 * stack_height_m`, look-at slightly above mid-column, collision spring so buildings do not eat the camera. Snap only on swap.

## 5. V0 definition (the token-survival cut)

Ship V0 when this is true on Windows F5. Everything else is V0.5 / V1.

V0 must:

1. Boot to title text `literally a stack of pylons` then a grey-city block or even a big plane with painted road stripes.
2. One possessable standard cone: WASD slide, Space hop, readable third-person camera.
3. At least 8 free upright cones in the world.
4. Slide/land into an upright cone → snap stack + click. Cap blocks at 12 ft with a dull knock.
5. Q drops bottom only; last body cannot drop.
6. E swaps to nearest cone in front; old body stays as physics debris/stack.
7. Camera dollies out as height grows.
8. Esc pause + F1 control map (UI, not README-only).
9. README with run instructions and the control table.
10. Project opens in Godot and runs with F5. Folder + editor. No installer.

V0 may fake:

- Joint shatter (a strong hit can unparent all pieces and dump them as rigid bodies).
- Mixed barrel/mini (add immediately after V0 if tokens remain).
- Silent dialogue box (one empty panel + cone portrait after first big hit).
- City (one intersection + one overpass box is enough).
- Traffic (one moving kinematic cube in a lane is enough).
- Audio (one click, one thunk).

V0 must not include:

- Worker van pickup animation
- Wet cement hole tool unless the core loop is already fun
- Radio voice
- Inventory, XP, names, faces, main-menu novel

If tokens are low, **plane + 12 cones + stack/drop/swap/camera/F1 is a successful V0**. The brief's city is V1 content.

## 6. Execution order (this is the professional sequence)

Do these in order. Each row is one Grok prompt + your F5.

| Slice | Name | You paste into Grok | You do locally | Done when |
| --- | --- | --- | --- | --- |
| 0 | Machine | nothing | Install Godot, git, empty project | F5 grey world |
| 1 | Soul on a plane | Programmer prompt + slice 1 spec only | Paste files, set main scene | Cone slides and hops |
| 2 | Stack | slice 2 only | Place second cone | Upright snap + cap math |
| 3 | Drop Q | slice 3 only | — | Bottom detaches, column settles |
| 4 | Hit dump | slice 4 only | Add a moving cube | Hit can separate pieces |
| 5 | Soul swap E | slice 5 only | Third cone | Mid-stack swap keeps above |
| 6 | Pause / F1 / title | slice 6 only | — | Controls UI exists |
| 7 | Mini + barrel | slice 7 only | — | Mixed cap still in meters |
| 8 | Silent box | slice 8 only | — | Empty box + portrait flags |
| 9 | Yard, not city | slice 9 only | — | One block, overpass box, 30 props |
| 10 | Dumb car | slice 10 only | — | One lane vehicle can scatter a stack |
| 11 | No-softlock | slice 11 only | — | Fall off map → nearest pavement |
| 12 | Joints upgrade | slice 12 only | Playtest 10 and 22 | Believable chunks |
| 13 | Tile streamer | last | Only if FPS holds | Arterial + downtown canyon |
| 14 | Toys | optional | Cut freely | Cement, gallery, van stub |

Original brief §13 is correct. The mistake is asking one agent to do §13.1 through §13.12 in a single completion.

## 7. Slice specs (paste one at a time)

### Slice 1 — empty world, one cone, slide, jump, camera

Create:

- `project.godot` (if needed): main scene `scenes/twin_falls.tscn`, autoload `GameConstants`
- `scripts/game_constants.gd`
- `scripts/soul_body.gd` (CharacterBody3D)
- `scripts/camera_rig.gd`
- `scenes/player/standard_cone.tscn` (mesh + collider only)
- `scenes/twin_falls.tscn`: StaticBody plane, one cone instance, camera rig, DirectionalLight, WorldEnvironment
- Input map: move_left/right/forward/back, jump, drop, swap, pause, controls, dialogue_advance

Movement feel:

- Instant heading from WASD
- Ground accel high, air accel tiny
- Jump once, no double
- Squash on land (scale y 0.92 then return)
- Camera behind + above, no stack dolly yet

Do not add a second cone.

### Slice 2 — stack + cap + camera dolly

- `scripts/cone_piece.gd` (type, height, extra, upright check)
- `scripts/stack_controller.gd`
- Snap on body-enter or land if target upright and `new_height <= CAP_M`
- Refuse + knock sfx stub (print is fine)
- Camera boom uses stack height

### Slice 3 — drop bottom

- Q: if count==1, failed click; else detach index 0, spawn free rigid piece, remaining pieces keep order and fall/settle with a velocity clamp so they do not orbital-launch

### Slice 4 — hit separation (cheap)

- Moving `AnimatableBody3D` cube on a path
- On impulse or area hit above threshold: unparent all, spawn rigid copies, soul stays in what was the bottom piece or the current anchor
- Good enough. Real joints are slice 12.

### Slice 5 — soul swap

- Ray or short shapecast from camera/look
- Range from constants
- Deposit current column as free rigids (or one group)
- Possess target; if target had pieces above, take those with you
- Camera snap allowed

### Slice 6 — UI shell

- Title label on boot 2.0s
- `pause_menu.tscn`, `controls.tscn`
- F1 and pause button show the control table from the brief
- Esc pauses physics-time

### Slices 7–14

Only after 1–6 are green on your machine.

## 8. How to talk to Grok so you do not run out of tokens

1. New conversation per slice once context gets long. First message: "Read STUDIO.md slices 0–N. Implement slice N+1 only. Here is the current file tree and the 20-line summary of what already works."
2. Never paste the original brief again. Point at this playbook.
3. When Grok dumps 15 files, apply them, F5, then send **only** the debugger error + what you pressed.
4. If Grok starts writing traffic AI, wet cement, or a skill tree, reply: "Stop. Slice N only."
5. Keep a running `STATUS.md` in the repo with 10 bullets max. That is the new context, not the brief.
6. Prefer "replace function X in stack_controller.gd" over "rewrite the project".
7. After V0, archive the chat. Start a "city pass" chat with only city constraints + perf budget.

`STATUS.md` template:

```
Engine: Godot 4.x.x  Renderer: Forward Plus
Works: slide, jump, camera, stack snap, cap knock
Broken: drop launches column
Next: slice 3 settle clamp
Cut: van, radio, cement
FPS: 120 on plane with 12 cones
```

## 9. Windows run / export

Dev:

- Open project folder in Godot → F5
- Main scene must be set or F5 will ask every time

Ship folder (not an installer):

- Project → Export → Windows Desktop
- Include `.exe` + `.pck` together
- README: "Install Godot 4.x or run the exported exe. F5 in editor. Controls: F1"

## 10. What Grok cannot do for you

- Feel. You have to slide a 12-foot stack into a curb.
- Mid-range FPS on your GPU.
- Godot inspector click-paths if the generated `.tscn` is malformed — paste the load error.
- Custom art that is cheaper than CylinderMesh. It is not cheaper.

If a slice is "impossible" (usually 22 rigid joints + 40 cars), cut the cars.

## 11. First message to send after this playbook exists

Use the Gameplay Programmer hat + Slice 1 spec. Do not attach the original brief.

When Slice 1 runs, send playtest notes, not a new vision document.
