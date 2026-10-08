extends RefCounted

## Chunk contract for the road network. 500 m chunks.
## Diameter 1 loads only the chunk the player is in.
## A chunk is only an ownership cell. Road modules are never cut to fit one.
## Streets are planned in world space, so a later neighbor can continue them.
const CHUNK_SIZE_M := 500.0
const ACTIVE_CHUNK_DIAMETER := 1


static func chunk_of(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(int(floor(world_x / CHUNK_SIZE_M)), int(floor(world_z / CHUNK_SIZE_M)))


static func chunk_origin(chunk: Vector2i) -> Vector2:
	return Vector2(float(chunk.x) * CHUNK_SIZE_M, float(chunk.y) * CHUNK_SIZE_M)


static func active_window(center_chunk: Vector2i) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	var radius: int = ACTIVE_CHUNK_DIAMETER / 2
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			chunks.append(center_chunk + Vector2i(x, z))
	return chunks
