extends SceneTree
## Raycast the imported '-col' collider of a curb-kit glb at listed points: -- <res glb> x,z,expected_y;...
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var root := Node3D.new(); get_root().add_child(root)
	root.add_child((load(a[0]) as PackedScene).instantiate())
	await physics_frame; await physics_frame; await physics_frame
	var space := root.get_world_3d().direct_space_state
	var worst := 0.0
	for p in a[1].split(";"):
		var v := p.split(","); var x := float(v[0]); var z := float(v[1]); var e := float(v[2])
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -1, z))
		var h := space.intersect_ray(q)
		var y: float = h.position.y if h else -99.0
		worst = max(worst, abs(y - e))
		print("RAY %s x=%.3f z=%.3f hit_y=%.4f expected=%.4f" % [a[0].get_file(), x, z, y, e])
	print("RAYWORST %s %.4f" % [a[0].get_file(), worst])
	quit()
