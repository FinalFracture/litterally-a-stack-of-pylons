# Status (Milestone 1 + M1.1, 2026-10-08)

- **World:** fixed default seed `20261008`. The same seed gives the same city (checked by hashing road, sidewalk and building transforms across runs). Only the centre chunk (0,0, 500 m) loads. There is no ring and no streaming.
- **Spawn:** on a sidewalk near the chunk centre, worked out from the generated layout. Respawn after a fall goes to the nearest sidewalk inside the chunk.
- **Test hooks:** `PYLONS_SEED`, `PYLONS_SPAWN`, `PYLONS_MAX_FPS`, `PYLONS_KEYMOUSE`, `PYLONS_LOGS`, as env vars or `--` arguments. A `PYLONS_LAUNCH` replay line prints at boot.
- **Controls:** Shift = swap, E = take the top cone, left click = add to stack, right click = drop one. Q and R are removed. F and X are reserved.
- **Stacking:** no height cap; a 40-cone stack works. Mixed stacks sit at the right height: only same-kind pieces nest, and everything else sits on top.
- **World cones:** rigid bodies at about 1.4 kg (the shipped 18" model; minis 0.9 kg), with a low custom centre of mass and a taper plus square-base collider. They start asleep. A car hit uses real physics, with a cap on the imparted speed and a slight random spin. Cars' solid colliders start at bumper height (0.22 m), so a hit strikes the cone above its centre of mass and tips it over.
- **Audio:** click, knock, thunk and dull click play as 3D one-shots. Click, knock and dull click use the Asset Manager's CC0 set (see `Sounds_Music/sfx/CREDITS.md`). Thunk is still a synthesized placeholder, because the CC0 set has no thunk slot.
- **Logs:** traffic telemetry and debug prints are off unless `PYLONS_LOGS=1`.
- **Not done yet (out of scope for M1):** acceleration tipping, wreck-to-physics and towing, per-road speed limits, bus stops, vehicle rescale, unused-asset cleanup.
- **Traffic determinism:** the city layout is exactly repeatable per seed, but traffic is only roughly repeatable. Traffic, driver choices and car-hit spin all draw from Godot's global random generator (seeded from the world seed), and physics timing changes the order of those calls. Exact replays would need a seeded RNG per car.
- **Known gaps:** pedestrians still walk the old hard-coded loop. Barrel-on-barrel stacking is unchanged (deferred). Rendered feel, camera, audio and frame rate still need checking on real hardware.
