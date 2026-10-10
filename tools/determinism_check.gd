extends SceneTree
## Determinism check (M2). Generates the same chunks twice, in different orders and on
## different threads, and compares content hashes; also checks the 64-bit chunk seed
## against reference values computed independently (Python splitmix64).
##
##   godot --headless --path . -s res://tools/determinism_check.gd -- [--coords=0,0;1,0;-1,2;-3,-3] [--out=user://determinism.json]
## Exit code 0 = all hashes and seeds match.

const REFERENCE_SEEDS := {
	# world seed 20261008, from tools/reference_chunk_seed.py
	Vector2i(0, 0): 7447561036809819406,
	Vector2i(1, 0): 9033199526367555690,
	Vector2i(-1, 2): 6255139788971471608,
	Vector2i(-3, -3): 2777408332646467760,
}

var coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 2), Vector2i(-3, -3)]
var out_path := "user://determinism.json"


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--coords="):
			coords.clear()
			for part in a.substr(9).split(";"):
				var xy := part.split(",")
				coords.append(Vector2i(int(xy[0]), int(xy[1])))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	var cfg: Script = load("res://scripts/world/world_config.gd")
	var seed := 20261008
	var ok := true
	var rows: Array = []
	for c in coords:
		var s: int = cfg.chunk_seed(seed, c)
		var ref: Variant = REFERENCE_SEEDS.get(c)
		var match_ref: bool = ref == null or int(ref) == s
		ok = ok and match_ref
		print("DET seed %s -> %d %s" % [str(c), s, "" if ref == null else ("ref OK" if match_ref else "REF MISMATCH %d" % int(ref))])
	# Pass A: one generator, coords in order, main thread.
	var gen_a: Resource = load("res://scripts/world/road_chunk_generator.gd").new()
	gen_a.prepare()
	var hash_a := {}
	for c in coords:
		var d: RefCounted = gen_a.generate(c, seed)
		hash_a[c] = d.get("content_hash")
		print("DET A %s %s (%.0f ms)" % [str(c), hash_a[c], d.get("gen_usec") / 1000.0])
	# Pass B: a fresh generator, reverse order, all in parallel on worker threads.
	var gen_b: Resource = load("res://scripts/world/road_chunk_generator.gd").new()
	gen_b.prepare()
	var boxes := {}
	var ids: Array[int] = []
	var rev := coords.duplicate()
	rev.reverse()
	for c in rev:
		var box := {"h": ""}
		boxes[c] = box
		var cc: Vector2i = c
		ids.append(WorkerThreadPool.add_task(func() -> void: box["h"] = gen_b.generate(cc, seed).content_hash))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	for c in coords:
		var hb: String = boxes[c]["h"]
		var same: bool = hb == str(hash_a[c])
		ok = ok and same
		print("DET B %s %s %s" % [str(c), hb, "MATCH" if same else "MISMATCH"])
		rows.append({"coord": [c.x, c.y], "chunk_seed": str(cfg.chunk_seed(seed, c)), "hash_a": hash_a[c], "hash_b": hb, "match": same})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"world_seed": seed, "ok": ok, "chunks": rows}, "  "))
	print("DET %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
