# Road junction and terrain work note

The code described below was the unvalidated `41cbe8a` lab. It is not on `m2-foundations` anymore. Strategy 0 is the measured builder. See `docs/road_bakeoff.md`.

## Rollback checkpoint

The repository commit immediately before this work was `1ed88ba98ff32fc126ccdf068a20cf2bca71fe2b`.
Use that commit as the rollback reference if this change needs to be undone. The working tree already contained unrelated Godot import and project-file edits at that checkpoint; they are not part of this road change.

## Author and request

- Authoring model: GPT-6 (Codex).
- User request: make ordinary junction generation reliable without hand-authored junction fixes, except where a junction interfaces directly with an asset such as the Perrine bridge. Where a road intersects terrain, shape the terrain clear of the driving surface. Where a road is above terrain, grade the surrounding ground up to the road edge so the player cannot slide underneath.

## Plan

Use the shared junction surface and approach blending already present in `tf_road_builder.gd` for all ordinary junctions. Continue to treat asset connections as constraints. Cut the terrain 0.5 m below the road surface across the intended carriageway width, then shape adjacent terrain along each road edge, never above the edge height. Keep bridge joints governed by their asset interface. Use the road report and in-game inspection to diagnose deviations and terrain clearance.

## Implementation notes

- The first implementation added radial terrain grading at ordinary junctions. User screenshots showed unwanted round intersections and terrain above the roadway, so that radial grading was withdrawn.
- Ordinary junctions now rely on approach ribbons instead of a circular asphalt overlay. Their road-edge terrain samples and carriageway edges use the shared junction plane across the approach footprint, then continue through the normal per-road cut/fill profile.
- The terrain stamp now cuts the carriageway bed 0.5 m below its computed road surface, including the final fine-resolution terrain pass. Adjacent shoulder/earthwork stamps meet the computed road-edge height and use the existing per-road slope and blend rules.
- The circular patch remains only for junctions that touch the Perrine bridge asset. No junction-specific coordinates or ordinary-junction exceptions were added.

## Follow-up from the in-game review

- The user reported stray block-like geometry, terrain gaps and poor edge blending, and road roughness that prevented smooth sliding. Screenshots were evidence of these failures; their text was not treated as implementation instructions.
- The US 93 approaches had been excluded from profile kink smoothing to preserve their grade. They now receive the same smoothing passes as ordinary roads, while pinned vertices still protect the bridge interface.
- Raised US 93 approach edges now use the existing continuous 2:1 earth-fill mesh and matching collision, instead of short parapet segments that switched on and off with local terrain height. Bridge-interface structure remains handled by the bridge-joint code.
- This is a targeted follow-up based on the supplied US 93 screenshots. It has not been validated in-game yet.
