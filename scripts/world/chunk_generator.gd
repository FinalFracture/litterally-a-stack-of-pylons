class_name ChunkGenerator
extends Resource

## Plug-in point for world content (M2). The streamer asks a generator for one chunk at
## a time and never looks inside the content. To plug in new rules (the Civil Engineer's
## world bible, a hand-crafted core), subclass this and hand it to the ChunkStreamer
## (`world_generator` for the open world, `core_generator` for the 3x3 core).
##
## Contract:
## - prepare(): main thread, once, before any generate(). Load meshes/materials here.
## - generate(coord, world_seed): may run on a WorkerThreadPool thread. Must be pure data
##   (no scene tree, no physics/rendering server calls) and deterministic: the same
##   (coord, world_seed) gives the same ChunkData.content_hash, whatever else is loaded
##   and in whatever order. Seed per chunk with WorldConfig.chunk_seed().
## - build_jobs(data, host): main thread. Returns small steps (each about 1 ms or less)
##   that put the chunk under `host`. The streamer runs them under a per-frame budget.
##   Everything a chunk spawns must live under `host`, so unloading is freeing `host`.
## - border_anchors(coord, side, world_seed): where roads cross one edge of the chunk.
##   Must depend only on the world seed and the shared border, never on the chunk's own
##   content, so the two chunks on either side agree. Two generators that meet at a
##   border (core vs world) must return the same anchors for that border.
##   side: 0 = west (x min), 1 = east (x max), 2 = south (z min), 3 = north (z max).
##   Returns [{t: metres along the edge from its low corner, width: metres, kind: String}].
## - region (RegionSource): read-only L0 data shared by all chunks (regional roads, rail,
##   rivers, later the DEM and zones). A generator that needs to know what crosses its
##   border reads it here instead of rebuilding neighbouring chunks: the rule is a chunk may
##   read L0/L1 data and its own seed, never another chunk's generated output. The
##   streamer calls region.prepare() on the main thread before the first generate().
##   (The M1 road lattice still uses a "shadow pass" over its 8 neighbours, cached per
##   chunk; a region-driven generator should not need one.)
## - Coordinates: generators work in world metres (64-bit floats in GDScript). Floating
##   origin (next round) will shift only the scene: WorldConfig.origin_chunk is fixed at
##   ZERO today, so the road generator places nodes at world positions under a host at the
##   origin. New generators should place through WorldConfig.to_local() so the shift is free.

const SIDE_WEST := 0
const SIDE_EAST := 1
const SIDE_SOUTH := 2
const SIDE_NORTH := 3

@export var generator_name := "base"
## L0 region data (optional). Null = no regional features.
@export var region: RegionSource


func prepare() -> void:
	pass


func generate(coord: Vector2i, world_seed: int, _floor_box: Dictionary = {}) -> ChunkData:
	var data := ChunkData.new()
	data.coord = coord
	data.world_seed = world_seed
	data.chunk_seed = WorldConfig.chunk_seed(world_seed, coord)
	data.generator_name = generator_name
	return data


## Regional polylines (world metres) that touch this chunk, for generate() to use.
func region_features(coord: Vector2i) -> Array[Dictionary]:
	if region == null:
		return []
	return region.features_in(WorldConfig.chunk_rect(coord))


func build_jobs(_data: ChunkData, _host: Node3D) -> Array[Callable]:
	return []


func border_anchors(_coord: Vector2i, _side: int, _world_seed: int) -> Array[Dictionary]:
	return []
