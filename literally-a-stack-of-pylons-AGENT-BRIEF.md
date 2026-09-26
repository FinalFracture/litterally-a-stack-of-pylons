# AGENT BRIEF — literally a stack of pylons

You are a master gameplay programmer, technical designer, and Godot 4 specialist. Build a complete, playable 3D game from this brief. Do not ask the user to fill gaps unless a requirement is truly impossible. Prefer a working game over a perfect engine. Do not add RPG systems, inventories, skill trees, worded NPC dialogue, crafting, multiplayer, or a main-menu novel.

Game title (exact, lowercase): **literally a stack of pylons**

Engine: **Godot 4.x** (4.3+ if available). Forward Plus or Compatibility renderer — pick whichever stays smooth on a mid-range Windows PC. Project language: **GDScript**. Desktop target: Windows.

Your job is to create the Godot project, implement the systems below, generate a large-but-cheap city, and leave the project runnable with `F5`. Check in a short `README.md` with how to run it and the control map.

---

## 1. Player fantasy (non-negotiable)

The player is not a hero cone. The player is a **soul that inhabits traffic-control plastic**.

- No arms, no legs, no walk cycle, no faces, no names in UI.
- Locomotion **looks like sliding**. Jump is a vertical hop of the current body.
- Other cones can be collected into a stack if they are **upright**.
- The soul can **swap** into any other traffic cone or barrel in range.
- Dialogue exists, but **boxes are empty**. The portrait *is* the line.

Tone: deadpan civic comedy. Public-works training video that escaped containment. Signs in the world may have real printed words (`DETOUR`, `WET CEMENT`). Living plastic never uses words.

---

## 2. Units and stack cap

Use meters internally. Author constants from imperial spec:

| Spec | Value | Meters |
|---|---|---|
| Standard cone height | 18 in | 0.4572 |
| Added height per extra stacked standard cone | 6 in (nesting) | 0.1524 |
| Maximum stack height | 12 ft | 3.6576 |
| Suggested standard cone base diameter | ~10–11 in | ~0.28 |
| Small cone height | ~12 in | 0.3048 |
| Small cone extra stack height | ~4 in | 0.1016 |
| Barrel / drum height | ~36–42 in | ~1.0 |
| Barrel extra stack height | ~14–16 in | ~0.38 |

**Cap rule:** measured from ground contact to the highest point of the possessed body. Player cannot stack a piece if it would exceed **12 feet**. Different sizes may mix. Reject the attach and play a dull plastic knock if the cap would break.

For a stack of only standard 18" cones, max count is:

`0.4572 + 0.1524 * (n - 1) <= 3.6576` → **n = 22**

Do not hard-lock count at 22 if the player mixes barrels and minis; lock **height**.

---

## 3. Body types

Three possessable prefabs. Same soul, different mass / COM / mesh.

1. **Standard pylon** — orange, white stripe, hollow-look but solid collider.
2. **Small cone** — same language, shorter, lighter, easier to knock down.
3. **Barrel / drum** — orange-and-white barrel, heavy, wide, high extra height, worse slide.

No facial features on any mesh. Optional later cosmetics (mustache, glasses, tire stamp, bend, sticker, electrical-tape ribbon) are **meshes/decals parented to the cone**, never eyes or mouths.

A cone is **stackable** only when upright: up-vector within a generous tolerance of world up (start at ~25–30 degrees, tune). Sideways or flat = debris until physics rights it.

Stacking validity **ignores cosmetics and damage**. A bent, dirty, tracked cone stacks like a factory cone if it is upright. Do not simulate dents affecting sockets.

---

## 4. The stack

### 4.1 What “you” are

The possessed object is either:

- a single cone/barrel, or
- a **column of attached pieces** the soul currently owns.

The soul is the whole possessed column, not a marked segment.

### 4.2 How pieces attach

- Contact an **upright, unpossessed** piece with the possessed body (slide into it or land on it after a jump).
- Snap into a nest socket on the **top** of the current stack (or onto the top of a mid-air land).
- Play a firm click. Parent / joint it into the stack.
- Apply each piece’s extra-height value. Refuse if cap exceeded.
- A knocked-over piece must be made upright by **physics** before it can attach. Player may ram the base, bump curbs, use jump landings, get hit by cars, etc. No “right cone” button.

### 4.3 Joints and hit separation

Pieces in a stack are physically joined (joints, custom stiff springs, or locked compound body + breakable sub-joints — your call, but it must survive 22-high columns and still break believably).

When an impulse hits the body, **the physics engine decides the break pattern**:

- all pieces separate
- two or three **chunks** of still-joined cones plus singles
- only the top or a mid section pops
- nothing breaks (glancing blow)

Do **not** use a flat “HP bar” to decide this. Use impulse magnitude, direction, and which segment was hit. Chunks that stay joined keep their internal sockets until another hit.

After a break:

- The soul **stays with whatever chunk still contains the soul anchor** (see §5).
- Other chunks become world physics objects and can be re-collected if they settle upright.

### 4.4 Center of mass

- A single cone/barrel is **bottom-heavy**. Hard to keep tipped. Tends to self-right on mild slopes.
- A stack **loses that advantage** as it grows. Tall stacks are tippy, sway, catch wind if you add a cheap lateral force in open avenues, and fall off awkward ledges.
- Dropped / deposited stacks use the same COM rules.

### 4.5 Drop (Q)

**Drop detaches the BOTTOM piece only.** Never drop a chunk. Never drop from the top.

Sequence:

1. If stack height is 1, drop does nothing (or a tiny failed-click). You cannot drop your last body.
2. Detach the current bottom piece.
3. Deposit it in place, slightly behind or under the column, as a free physics body.
4. Remaining pieces are now the possessed stack and must **settle onto the ground through physics** (they just lost their foundation). Do not teleport them. A short assist (limit insane explosions) is OK if the column would otherwise launch into orbit.
5. Deposited piece is upright if the ground under it is reasonable; if the surface is awkward, it may tip. Bottom-heavy singles should often stay up. Deposited multi-stacks (from soul swap, §5) are much more willing to fall.

There is no “drop whole stack” button. Whole-stack deposit is a **player combo**: drop bottom piece, then soul-swap into that lone piece, which leaves the rest behind as an unpossessed stack subject to deposit physics.

---

## 5. Soul swap (E)

Range: a generous cone-length or two, based on look direction / center aim, any possessable pylon, mini, or barrel in the world — including pieces inside *other* stacks and pieces inside your own stack.

On swap:

1. Current possessed column is **deposited as an unpossessed physics stack** (or single). Same tipping rules as drop. Tall deposited stacks should often wobble or spill. That is intended.
2. Soul moves into the target piece.
3. If the target was a **lone piece**, player is now that single body.
4. If the target was **in a stack**, player becomes **that piece plus everything stacked above it**. Pieces below the target stay behind as their own deposited stack/chunk.
5. Camera and control snap to the new body.
6. Optional: empty dialogue box with the new body’s portrait. No text.

Soul anchor for break resolution: after a physics shatter, keep the piece the soul last inhabited plus any pieces that remained joined **above** it. Pieces that ripped off below or beside become world objects.

Swapping onto a barrel in the middle of a mixed tower must work. Swapping onto a small cone under an overpass must work.

---

## 6. Movement

**Slide (WASD / left stick):**

- Instant direction, no walk cycle, no foot IK.
- Visual: translation + slight squash/stretch and a stripe smear at speed.
- Grounded only for strong control; tiny air steer after jump.
- Taller / heavier → more momentum, worse steering, longer brake.
- Rain-slick materials later if cheap; not required for first playable.

**Jump (Space):**

- Single hop. No double jump. No flip.
- Whole possessed body goes up together.
- Jump height scales **weakly** with mass/height so a 12-foot tower is not a rocket. A single small cone jumps snappier and lower-distance.
- Ceiling / awning / overpass bonk: apply downward cancel + impulse; joints may break from the hit. Do not delete pieces.
- Landing on an upright free cone tries to stack it on top (cap permitting).

Movement must feel toy-like and readable, not simulationist truck-driving.

---

## 7. Camera

- Third person, behind and slightly above the possessed body.
- **Dolly out as stack height grows** so the full column and the road stay framed. Never hide the bottom piece if possible — the bottom piece is the scrape.
- Collision-aware boom so it does not bury in buildings.
- Soft follow, no motion sickness snaps except on soul swap (short cut is fine).
- Reset / recenter optional (middle mouse or a key).

---

## 8. Silent dialogue

Implement a real dialogue UI that contains **no words**.

Rules:

- Box looks like a proper RPG speech panel (frame, tail optional).
- **No nameplate. No names. No “…” text.** Empty interior.
- Portrait sits on the box edge: the speaking cone mesh or a render of it.
- Portraits have **no faces**. Decoration only: bend, dirt, tire track decal, stolen glasses, mustache mesh, crack, bird mess, tape ribbon, gallery-plinth, older paint, etc.
- **Cones / barrels only.** Hydrants, cars, and cement do not get boxes in this version. World signs may still show printed municipal text.
- Timing: run physics of the event first, **then** open the box after the body has mostly settled. Short world pause while the box is up (player can advance). Do not let a box appear mid-tumble as the first implementation.
- Advance: **LMB or Space**. If Space would jump, consume it as advance while a box is open.
- Gags to implement on day one:
  - After a serious car hit: box + portrait with tire stamp and a bent cone.
  - After first successful stack: two portraits, too close together, both silent.
  - After soul swap: new body’s portrait, still silent.
- Do not write a dialogue script file full of strings. Drive portrait variants from cone state flags.

---

## 9. Controls

| Action | Keyboard | Notes |
|---|---|---|
| Slide | WASD | |
| Jump | Space | Also advances dialogue if a box is open |
| Drop bottom cone | Q | No-op at height 1 |
| Soul swap | E | Aimed / nearest valid in front |
| Advance box | LMB or Space | |
| Pause | Esc | |
| Show controls | F1 and a **Controls** button on pause / title | Must display the map |

Include a **Controls** screen (pause menu button + F1) that shows this map as UI, not as a paragraph in a README only.

Optional pad support if cheap: left stick move, A jump, X drop, Y/RB swap.

---

## 10. City

The user wants a **considerably large city** that still **loads and plays smoothly**. You choose layout, block kit, and streaming strategy. Constraints:

- Feels like a real metro: arterial roads, downtown canyons, side streets, at least one overpass, sidewalks, a civic building readable from far away, night-work lights somewhere.
- **Cheap art:** box buildings, repeated facades, simple street furniture, asphalt, sodium-style lights. Skybox + distant trains / skyline do the “grand.”
- Performance budget: stable play on one possessed stack of ~10–22 pieces plus traffic. Use instancing, baked or no GI, simple colliders (boxes/cylinders), occlusion culling, and **chunk streaming or paging**. Do not spawn the entire city’s rigid bodies on frame 1.
- Traffic: enough moving vehicles to hit the player and create comedy. Dumb lane-following is fine. Cars should try to brake for a cone in their lane but may fail. Trucks are ruder.
- At least one worker or collection-adjacent threat is desirable (a public-works van that tries to pick up loose cones) but **cut it** if it threatens stability. Cars + physics come first.
- Place **many** free cones and some barrels and minis across the map so stacking and swapping are always available.

You own map composition. Prefer a tiled modular block set (intersection, straight, corner, overpass, plaza) stamped across a large grid over a unique snowflake city.

### Suggested municipal toys (implement as many as stay stable)

Treat these as content, not new engines:

- Hold a lane until a truck moves (it is slow).
- Guard a wet-cement rectangle; jump or fall into it leaves a cone-shaped hole.
- Reach a civic building without being collected / vanished by a van if the van exists.
- An overpass that punishes tall stacks.
- A gallery window with a cone on a plinth.
- A manhole / service-looking pit with older-paint cones.
- Radio is optional and **must not speak player-facing sentences about feelings**. A distant garbled traffic bed is enough.
- Stadium or billboard that reacts if cheap.

Do not block shipping on easter eggs. Ship movement, stack, drop, swap, hit-break, silent box, city traversal first.

---

## 11. Look

- Clear orange PVC, white stripe, grey city, readable silhouettes.
- Title on boot: **literally a stack of pylons**
- UI sparse: pause, controls, maybe a tiny stack-height tick. **No health, no XP, no named quest tracker.**
- If you need a fail / wake-up: soul can snap back to the largest remaining upright chunk, or to a nearby cone, rather than a game-over screen. Avoid softlocks if the possessed body falls off the map — respawn on nearest pavement with a silent box.

---

## 12. Project structure (suggested)

```
project.godot
README.md
assets/
  meshes/
  textures/
  audio/          # thunks, tire, click, distant city bed
scenes/
  main.tscn
  player/
  props/
  vehicles/
  ui/
    dialogue_box.tscn
    pause_menu.tscn
    controls.tscn
  city/
    tiles/
scripts/
  stack_controller.gd
  soul.gd
  cone_piece.gd
  joint_break.gd
  camera_rig.gd
  dialogue_silent.gd
  city_streamer.gd
  vehicle.gd
  pause_ui.gd
```

Name things clearly. Put tunables in one `game_constants.gd` autoload (heights, cap, joint break impulse, swap range, camera distances per height).

---

## 13. Implementation order (follow this)

Do not start by generating 200 buildings.

1. Empty world, ground, one standard cone, slide + jump, third-person camera.
2. Second cone, upright-only snap stack, height cap math, camera dolly.
3. Drop bottom piece + remaining column settles.
4. Breakable joints / chunk separation from a moving cube or car impulse.
5. Soul swap into a third cone; deposit old body; mid-stack swap keeps above.
6. Silent dialogue box + portrait-from-state after a hit.
7. Barrel + small cone prefabs, mixed stacks, cap still in feet.
8. Pause + F1 / Controls button map.
9. Modular city tiles + streamer + enough road to feel large.
10. Traffic + a handful of toys / eggs if frame rate holds.
11. Polish: audio thunks, stripe smear, title, no-softlock respawn.
12. Playtest pass: 22-standard cap, swap-deposit combo, overpass bonk, car scatter.

At every step the project must run.

---

## 14. Acceptance criteria

The game is V0-complete when all of the following are true:

- Boots to a playable city with the title visible at least once.
- Player can slide, jump, stack upright cones, and is blocked by the 12-foot cap.
- Q drops only the bottom piece; last piece cannot be dropped.
- Hits can split the stack into singles and multi-cone chunks via physics.
- E swaps into standard, small, and barrel bodies; leftover column is deposited and may tip.
- Drop-then-swap deposits the remainder of a stack as intended.
- Downed cones only rejoin after physics leaves them upright.
- Camera pulls back as the stack grows and keeps the column readable.
- Empty dialogue boxes appear after a hard hit with a damaged portrait and no text.
- F1 / Controls button shows the control map.
- Large city streams or pages; movement stays playable (target a stable framerate, not cinematic dumps).
- No names in dialogue. No faces on cones. No extra genres glued on.

---

## 15. What you must not do

- Do not wait for custom art beyond primitives / simple modeling.
- Do not invent spoken jokes or subtitle files.
- Do not implement a cone skill tree.
- Do not require online services.
- Do not hide the project behind an installer. Folder + Godot + F5.
- Do not ignore the bottom-drop rule or the 12-foot cap.
- Do not treat barrels as props only — they are possessable bodies.
- If something is too expensive (full traffic AI, worker pickup animation), stub it and keep the core loop.

---

## 16. First message to yourself after creating the project

Create the Godot project, add `game_constants.gd`, spawn a plane and one cone, implement slide + camera, commit mentally to the build order in §13, then continue without stopping until §14 passes or you hit a hard engine limitation. Document any limitation in `README.md`.

Build **literally a stack of pylons**.
