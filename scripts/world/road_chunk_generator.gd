class_name RoadChunkGenerator
extends ChunkGenerator

## Default world content: the M1 seeded road/district generator (scripts/road_network.gd)
## wrapped as a ChunkGenerator. Placeholder content until the world bible lands.
##
## Border continuity: arterial streets sit on a world-space lattice (stations every
## CROSS + 26 tiles, phase from the world seed per axis), so a street that leaves one
## chunk always lands on a street in the next. Road tiles are owned by the chunk they sit
## in, and a whole lane segment by the chunk of its near crossing. border_anchors()
## reports the lattice lines crossing each edge; tools/road_alignment_check.gd checks the
## real geometry against them on both sides of every border.

const _RoadNet := preload("res://scripts/road_network.gd")

var _kit: RefCounted
var _ground_mat: StandardMaterial3D
var _ground_mesh: BoxMesh
var _ground_shape: BoxShape3D


func _init() -> void:
	generator_name = "road_lattice_v1"


func prepare() -> void:
	if _kit != null:
		return
	_kit = _RoadNet.new()
	if not _kit.prepare_kit():
		push_error("Road modules failed to load.")
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_color = Color(0.30, 0.44, 0.22)
	_ground_mat.roughness = 1.0
	_ground_mesh = BoxMesh.new()
	_ground_mesh.size = Vector3(WorldConfig.CHUNK_SIZE_M, 0.5, WorldConfig.CHUNK_SIZE_M)
	_ground_shape = BoxShape3D.new()
	_ground_shape.size = _ground_mesh.size


func kit() -> RefCounted:
	return _kit


func generate(coord: Vector2i, world_seed: int) -> ChunkData:
	var t0 := Time.get_ticks_usec()
	var data := ChunkData.new()
	data.coord = coord
	data.world_seed = world_seed
	data.chunk_seed = WorldConfig.chunk_seed(world_seed, coord)
	data.generator_name = generator_name
	var rn = _RoadNet.new()
	var out: Dictionary = rn.stream_generate(world_seed, coord, _kit)
	data.road_rects = out["rects"]
	data.road_segments = out["segments"]
	data.drive_edges = out["drive_edges"]
	data.controls = out["controls"]
	data.junctions = out["junctions"]
	data.walk_boxes = out["walk_boxes"]
	data.blocks = out["blocks"]
	data.cone_sites = out["cone_sites"]
	data.portals = out["portals"]
	data.spawn = out["spawn"]
	data.stats = out["stats"]
	data.content_hash = out["hash"]
	data.payload = rn
	data.gen_usec = Time.get_ticks_usec() - t0
	return data


func build_jobs(data: ChunkData, host: Node3D) -> Array[Callable]:
	var jobs: Array[Callable] = [_ground_job.bind(data.coord, host)]
	var rn = data.payload
	if rn != null:
		jobs.append_array(rn.stream_jobs(host))
	return jobs


func _ground_job(coord: Vector2i, host: Node3D) -> void:
	# Grass under the whole chunk. Outside the world there is no chunk, so no ground: fall-off.
	var c := WorldConfig.chunk_center(coord)
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.position = Vector3(c.x, -0.45, c.z)
	var shape := CollisionShape3D.new()
	shape.shape = _ground_shape
	body.add_child(shape)
	var view := MeshInstance3D.new()
	view.mesh = _ground_mesh
	view.material_override = _ground_mat
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(view)
	host.add_child(body)


func border_anchors(coord: Vector2i, side: int, world_seed: int) -> Array[Dictionary]:
	var rn = _RoadNet.new()
	rn._reset_build(WorldConfig.chunk_center(coord))
	var window: Array[Vector2i] = [coord]
	rn._prepare_plan(world_seed, window)
	var origin := WorldConfig.chunk_origin(coord)
	var size := WorldConfig.CHUNK_SIZE_M
	# West/east edges are crossed by east-west streets (z stations); south/north by x stations.
	var along_z: bool = side == SIDE_WEST or side == SIDE_EAST
	var stations: Dictionary = rn._station_z if along_z else rn._station_x
	var arteries: Dictionary = rn._artery_z if along_z else rn._artery_x
	var low: float = origin.y if along_z else origin.x
	var out: Array[Dictionary] = []
	var keys: Array = stations.keys()
	keys.sort()
	for k in keys:
		var pos: float = float(stations[k])
		if pos < low or pos >= low + size:
			continue
		out.append({"t": pos - low, "width": rn.CROSS, "kind": "arterial" if arteries.has(k) else "street"})
	return out
