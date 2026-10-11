# HANDOFF-25 — Boat ramp v2 (cast concrete), fixes PT-TF-022 look

Target: `res://Models/twin_falls/tf_boat_ramp_8m_v2.glb` (v1 `tf_boat_ramp_8m.glb` untouched, still in the repo)
Source: `builds/twin_falls/boat_ramp_v2/` — `tf_boat_ramp_8m_v2.glb`, `.blend`, `.log.json`, `make_boat_ramp_v2.py` (Blender 5.2.2), `make_tex.py`, `tex/` (3 × 512² PNG, embedded in the glb; 1 m tile).

## Geometry
- 8.0 m overall: 7.6 m grooved deck (transverse anti-slip grooves, 100 mm pitch) + 0.2 × 0.15 m curbs both sides.
- 20 m long at 12 % (drop 2.4 m), 0.3 m slab, side skirts + head/toe cut-off walls down to 1.8 m below the deck (tolerates ~1.5 m of terrain mismatch).
- Lower third (last 6.67 m, deck below local y −1.6) = wet/algae materials.
- 88 tris, 4 materials = 4 draw calls (`tf_ramp_grooved`, `tf_ramp_grooved_wet_algae`, `tf_concrete`, `tf_concrete_wet_algae`). Godot AABB 8.0 × 4.35 × 20.0.
- Collision: `tf_boat_ramp_8m_v2_col-colonly` trimesh (copy of the render mesh) → StaticBody3D.

## Pivot (same as v1)
Origin = top edge centre on the deck surface (local y 0); ramp descends toward local −Z. Toe centre at (0, −2.4, −20). Swap the model path and the current placement still works.

## Developer note — placement (PT-TF-022)
The current placement `Lm_centennial_park_ramp` (2450, 0.03, −6600) is **157 m from the water**, and that's why it reads as a pale slab. Move it so the ramp **ends in the river**:
- Put the top edge at the bank, with the ramp axis (local −Z) pointing into the water, perpendicular to the shoreline.
- Set node y = water_y + 1.5, so the waterline crosses the ramp about 12.5 m down. The lower ~7.5 m are then submerged and the toe sits about 0.9 m under water, with the wet/algae band at and below the waterline.
- Rule of thumb: water_y should fall between node y − 1.2 and node y − 1.8. The toe must always be under water.
- Let the terrain meet the curbs/skirt. The skirt hides gaps up to 1.8 m below the deck.

## Checks (Blender, against the glb collider; `boat_ramp_v2_check_blender.log`)
10/10 OK, worst 0.000 m: deck at z −0.3 / −10 (centre and x ±3.5) / −13.4 / −19.7 = −0.036 / −1.200 / −1.608 / −2.364; curb tops at x ±3.9 = −1.050; rays past both ends hit nothing.
Render: `builds/twin_falls/renders/tf_boat_ramp_8m_v2_person.png` (water at −1.5, 1.8 m figure).
Not measured in Godot (no Godot on the box).
