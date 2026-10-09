class_name WorldConfig
extends RefCounted

## World layout for streaming (M2).
##
## The world is a square grid of 500 m chunks. Only a 3x3 window of chunks around the
## player is loaded at a time (WINDOW_RADIUS 1). The 3x3 block of chunks around chunk
## (0,0) is the "core" (CORE_RADIUS 1): the hand-crafted city centre goes there later,
## supplied by its own ChunkGenerator (see ChunkStreamer.core_generator).
##
## World edge: chunks outside +-world_half_m (metres from the origin, both axes) are never
## generated. There is no ground there, so anything that leaves the world falls off.
## Provisional size: +-2 km (8 x 8 chunks). The target is state-sized (tens of km); the
## streamer does not care about the size, so raising it is a config change:
## PYLONS_WORLD_HALF_M=N / --world-half-m=N, or DEFAULT_WORLD_HALF_M below.

const CHUNK_SIZE_M := 500.0
const WINDOW_RADIUS := 1
const CORE_RADIUS := 1
const DEFAULT_WORLD_HALF_M := 2000.0

# splitmix64 / xxhash constants as signed int64 (0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9,
# 0x94D049BB133111EB, 0xC2B2AE3D27D4EB4F).
const GOLDEN_GAMMA := -7046029254386353131
const MIX_1 := -4658895280553007687
const MIX_2 := -7723592293110705685
const MIX_Z := -4417276706812531889

static var world_half_m: float = DEFAULT_WORLD_HALF_M


static func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CHUNK_SIZE_M)), int(floor(z / CHUNK_SIZE_M)))


static func chunk_origin(chunk: Vector2i) -> Vector2:
	return Vector2(float(chunk.x) * CHUNK_SIZE_M, float(chunk.y) * CHUNK_SIZE_M)


static func chunk_center(chunk: Vector2i) -> Vector3:
	var o := chunk_origin(chunk)
	return Vector3(o.x + CHUNK_SIZE_M * 0.5, 0.0, o.y + CHUNK_SIZE_M * 0.5)


## Floating origin hook (world bible 03 §9; built next round). The scene origin sits at
## this chunk's corner; today it never moves (ZERO), so local == world. When it moves, the
## streamer shifts every loaded root by the same multiple of CHUNK_SIZE_M on a physics
## frame; generator data stays in world metres and only build/placement converts.
static var origin_chunk := Vector2i.ZERO


static func to_local(world: Vector3) -> Vector3:
	return world - Vector3(origin_chunk.x * CHUNK_SIZE_M, 0.0, origin_chunk.y * CHUNK_SIZE_M)


static func to_world(local: Vector3) -> Vector3:
	return local + Vector3(origin_chunk.x * CHUNK_SIZE_M, 0.0, origin_chunk.y * CHUNK_SIZE_M)


static func chunk_rect(chunk: Vector2i) -> Rect2:
	return Rect2(chunk_origin(chunk), Vector2(CHUNK_SIZE_M, CHUNK_SIZE_M))


static func chunk_min() -> int:
	return int(floor(-world_half_m / CHUNK_SIZE_M))


static func chunk_max() -> int:
	return int(floor((world_half_m - 0.001) / CHUNK_SIZE_M))


static func in_world(chunk: Vector2i) -> bool:
	var lo := chunk_min()
	var hi := chunk_max()
	return chunk.x >= lo and chunk.x <= hi and chunk.y >= lo and chunk.y <= hi


static func clamp_chunk(chunk: Vector2i) -> Vector2i:
	return Vector2i(clampi(chunk.x, chunk_min(), chunk_max()), clampi(chunk.y, chunk_min(), chunk_max()))


static func is_core(chunk: Vector2i) -> bool:
	return absi(chunk.x) <= CORE_RADIUS and absi(chunk.y) <= CORE_RADIUS


## The loaded window around `center`, clipped to the world. Nearest first.
static func window(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-WINDOW_RADIUS, WINDOW_RADIUS + 1):
		for dx in range(-WINDOW_RADIUS, WINDOW_RADIUS + 1):
			var c := center + Vector2i(dx, dz)
			if in_world(c):
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	return out


## Per-chunk seed: world seed + chunk coords. Same formula the road generator uses.
static func chunk_seed(world_seed: int, chunk: Vector2i) -> int:
	# 64-bit splitmix64 mix of (world_seed, cx, cz) (world bible 03 §2). The M1 two-step LCG
	# correlated neighbouring chunks; this doesn't. GDScript ints are 64-bit and wrap.
	var inner: int = splitmix64((chunk.x * GOLDEN_GAMMA) ^ (chunk.y * MIX_Z))
	var n: int = splitmix64(world_seed ^ inner) & 0x7FFFFFFFFFFFFFFF
	if n == 0:
		n = 1
	return n


## A per-feature seed under a chunk (or super-cell) seed, so adding a feature ("trees",
## "lots", "cones") never reshuffles the others. One RandomNumberGenerator per feature.
static func feature_seed(base_seed: int, feature: String) -> int:
	var n: int = splitmix64(base_seed ^ splitmix64(feature.hash() * GOLDEN_GAMMA)) & 0x7FFFFFFFFFFFFFFF
	return n if n != 0 else 1


## splitmix64 finaliser (Steele, Lea & Flood 2014). Constants written as signed 64-bit.
static func splitmix64(x: int) -> int:
	var z: int = x + GOLDEN_GAMMA
	z = (z ^ _lsr(z, 30)) * MIX_1
	z = (z ^ _lsr(z, 27)) * MIX_2
	return z ^ _lsr(z, 31)


static func _lsr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


static func key(chunk: Vector2i) -> String:
	return "%d,%d" % [chunk.x, chunk.y]
