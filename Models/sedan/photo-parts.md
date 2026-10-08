# Photo parts, one pass

Build a modular sedan the same way as the fleet cars: one side photograph, lofted, split into pieces, with one paint channel on the body and the doors. One script run writes the meshes. One Godot import checks them.

The builder that already does this is `C:\Users\upchu\AppData\Local\Temp\sedan_photo.py`. It reads `C:\Users\upchu\AppData\Local\Temp\fleet_mesh.py` and `C:\Users\upchu\AppData\Local\Temp\fleet_src\car.jpg`.

```
py -3 C:\Users\upchu\AppData\Local\Temp\sedan_photo.py
```

Then import once:

```
& "C:\Users\upchu\OneDrive\Desktop\sTUFF\Programming\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\upchu\onedrive\desktop\stuff\programming\python_projects\pylons\litterally-just-a-stack-of-pylons" --import
```

Copy the printed `LAYOUT` numbers into `scripts/sedan_parts.gd` only when they differ from the constants already there. Press F5 on `scenes/main.tscn`. Walk into the sedan. Each new touch picks a new paint color. Staying in contact does not roll again.

## Skip

- The remote 3D mesh call (`three_d.py`, `POST /v1/3d/generations`). This team gets HTTP 400: deferred endpoints cannot store the image or the mesh.
- A newly generated car photo. The fleet side picture is the style anchor. A fresh generation drifts.
- A vertex-color preview of the loft. The mesh is coarse, so vertex colors smear a good UV into a blur. Sample the texture at each preview pixel.

## Frame

Godot and glTF are Y-up, right-handed. The nose is local **-X**, the same nose `hit_cube.gd` already drives (`atan2(flat.z, -flat.x)` on `Heading`). The image's left end is the nose. Tire bottoms sit at local **y = -0.60**. Wheel radius is **0.32**, so the hub is at **y = -0.28**.

Right side of the car is local **-Z** (nose × up). A SpotLight looks along its local -Z. `rotation.y = +PI/2` aims that axis down the nose. Blinker rate is `angle_difference(previous_yaw, yaw) / delta`. A positive rate is a right turn and lights `BlinkFR` and `BlinkRR`.

## Photograph

One side view on a flat green field, the whole car in frame, even light, no ground shadow. `fleet_mesh.cutout` keys the green. `fleet_mesh.profile` supplies the silhouette and the two wheel centers. Use those centers. A second search for dark bulges will park both wheels at the tail.

Length along X is 3.50 m. Body half-width follows the fleet plan: narrower at the nose and tail, about 0.63 m through the doors.

## Texture

Write `Models/sedan/flank.png` as RGBA. That file is the paint channel.

- Paint pixels: blue dominates (`blue > red + 4` and `blue + 6 > green`), luma between 22 and 215. This includes the darker roof. Store `rgb` as grayscale shade (`luma / median_paint_luma * 0.78`) and **alpha = 1**.
- Everything else on the car (chrome, lamps, lettering): keep the photo rgb and **alpha = 0**.
- Windows: only on the tall middle of the silhouette, between 10% and 50% down the column, and only where the pixel is not paint. The hood is short, so it stays paint.
- Wheel disks: after the mask, punch a circle of radius `0.32 / scale` up from the tire bottom at each `profile` wheel center. Put the photo rgb back and set alpha to 0 so the hubcap is not paint.
- Roof, hood, and trunk caps share one UV: the median paint pixel. A texel parked on the last row disappears when the png is resized, and the roof renders black.
- Bumper caps can use a dark texel with alpha 0.

`scripts/sedan_parts.gd` preloads `flank.png` as a `Texture2D` and sets `use_photo` and `flank_tex` on one `ShaderMaterial`. Body paint and every door paint surface get that same material. `set_paint` writes `paint_color` once.

`shaders/sedan_paint.gdshader` is:

```
ALBEDO = mix(detail, paint_color.rgb * shade, mask)
```

With `use_photo`, shade and mask come from the texture. Alpha 1 tints. Alpha 0 keeps the photo.

## Pieces

One glTF node per material so Godot can override Paint and Glass and find the lamps by name.

| File | Nodes | Role |
| --- | --- | --- |
| `body.glb` | `Paint`, `Trim`, `Cabin`, `LampHeadL`, `LampHeadR`, `LampTailL`, `LampTailR`, `BlinkFL`, `BlinkFR`, `BlinkRL`, `BlinkRR` | Loft. Side quads inside a door rect are omitted. Wheel arches use the rocker, not the tire bottom. |
| `door_front.glb` | `Paint`, `Glass` | Hinge at the nose-side edge. Panel extends +X. Outer face at local z = 0.016. Window cells are Glass at z = 0.008. |
| `door_rear.glb` | `Paint`, `Glass` | Same hinge rule. Door bottom is the rocker line. |
| `windshield.glb` | `Glass` | Front and rear slope in car space. Glass is not also inside `body.glb`. |
| `wheel.glb` | `Rubber`, `Rim` | Hub at the origin, axle along Z. Tread is black. The disk UVs show `wheel.png`. |
| `axle.glb` | `Trim` | Brushed steel, half-length 0.62 so it meets the inner face of a wheel at z = 0.67. |
| `flank.png` |  | The shared photo and the paint mask. |

`wheel.png` is the square crop centered one radius above the silhouette bottom. Before the 256² resize, paint body-blue pixels (`blue > red + 12` and `blue > 70`) and green spill (`green > red + 25` and `green > blue + 10`) to near-black `(16, 16, 18)`. The crop otherwise keeps a blue fender ring on the tire.

Glass is `shaders/sedan_glass.gdshader` on the windshield and every door window. Wheels and axles never take the paint shader.

`sedan_parts.gd` places the parts. Right-side doors (`z < 0`) use `scale.z = -1`. The current layout, from the last `LAYOUT` line, is:

```
HALF_W   0.63
DOOR_F   x = -0.4957   y = -0.4226
DOOR_R   x =  0.274    y = -0.4163
WHEEL_R  0.32
WHEEL_Y -0.28
TRACK    0.67
AXLE_F  -1.1324
AXLE_R   1.0072
```

`sedan_drive.gd` spins wheels by `travel · nose / 0.32`. Nose is `-Heading.global_transform.basis.x`. Front doors open after the car has been still for about half a second and shut when it moves. Lamps emit only when `DirectionalLight3D.sun_up()` is false.

## Touch test

In `hit_cube.gd`, `_paint_test` runs for `vehicle_kind == "car"` when `wrecker` is false. Overlap with a body in group `soul` (or parented to one) on the rising edge calls `_roll_paint`, which sets `paint_color` through `SedanRig.set_paint`. The wrecker return in `_apply_kind` stays above the sedan assemble, so a wrecker never gets this mesh.

## Preview, then import

The script writes three pictures under `%LOCALAPPDATA%\Temp\sedan_preview\`:

- `sedan_red_side.png` and `sedan_white_side.png` — body and doors change together; wheels, lamps, and glass stay.
- `sedan_red_quarter.png` — roof and hood are the paint color; both axles are present; hubcaps read as the photo wheel.
- `mask.png` — green is paint, blue is glass. The hood and roof are green. The wheels are not.
- `wheel.png` — tire and silver hubcap, no green fringe, no blue fender ring.

`np.eye` needs `dtype=`. `np.eye(4, np.float32)` throws.

If those pictures match, import. Godot node names come from the glTF nodes above. `_retint` overrides `Paint` and `Glass` and hangs lights on the lamp nodes.

## GDScript

Explicit types. `:=` fails when the right-hand side is untyped. No `const` inside a function. No method named `_set`. A class-level `PackedStringArray([...])` does not parse; build it in a function. Preload `flank.png`. `Image.load` on that path warns and will not export.

## What will still look rough

The window band has small holes where a blue reflection counted as paint. Door edges show a seam at the pillar. The mirror is part of the flank photo, not its own piece. The wheel can keep a thin dark arc along the top of the tire. Roof and hood tops are a flat coat of the paint, which is how the other fleet roofs are finished.
