class_name ChunkData
extends RefCounted

## What a ChunkGenerator hands the streamer for one chunk. Plain data: built on a
## worker thread, read on the main thread. World-space metres throughout.

var coord := Vector2i.ZERO
var world_seed := 0
var chunk_seed := 0
var generator_name := ""
## Asphalt footprints: [{area: Rect2, name: String}]. Feeds City.on_asphalt / surface_at.
var road_rects: Array = []
## Map lines for the HUD: [{from: Vector3, to: Vector3, name, kind}].
var road_segments: Array = []
## Lane graph edges, same format as the old "road_drive_edges" meta:
## [{ax, az, bx, bz, kind, length, through, forward: PackedVector3Array, back: PackedVector3Array}].
## An edge may end inside a neighbour chunk; traffic only uses it while both ends are loaded.
var drive_edges: Array = []
## Traffic controls: [{pos, dir, cx, cz, mode: "light"|"stop", kind}].
var controls: Array = []
## Junction centres (Vector2).
var junctions: Array = []
## Sidewalk boxes: [{mid: Vector3, angle, length, width}]. Pedestrians walk these.
var walk_boxes: Array = []
## Building footprints (Rect2) for the HUD map.
var blocks: Array = []
## Cone stacks: [{at: Vector3, count: int, yaw: float}]. Stable id = seed:cx:cz:index.
var cone_sites: Array = []
## A sidewalk point near the chunk centre (spawn / teleport target).
var spawn := Vector3.ZERO
## Where roads actually cross this chunk's border: [{chunk, edge, x, z}] (edge west/east/south/north).
var portals: Array = []
var stats: Dictionary = {}
## SHA-256 over the generated content. Same seed + coords must give the same hash.
var content_hash := ""
var gen_usec := 0
## Generator-private state needed by build_jobs().
var payload: Variant = null
