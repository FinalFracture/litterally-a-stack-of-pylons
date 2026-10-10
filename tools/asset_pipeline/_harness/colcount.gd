extends SceneTree
## Counts collision bodies/shapes per imported glb or tscn (Asset Manager; temp project only).
func _init():
	for p in OS.get_cmdline_user_args():
		var n: Node = load(p).instantiate()
		var bodies := n.find_children("*", "CollisionObject3D", true, false)
		if n is CollisionObject3D: bodies.append(n)
		var shapes := n.find_children("*", "CollisionShape3D", true, false)
		var desc := []
		for s in shapes: desc.append(s.shape.get_class() + ("(faces=%d)" % (s.shape.get_faces().size() / 3) if s.shape is ConcavePolygonShape3D else ""))
		var kinds := []
		for b in bodies: kinds.append(b.get_class() + (" mass=%s" % b.mass if b is RigidBody3D else ""))
		var meshes := n.find_children("*", "MeshInstance3D", true, false).size()
		print("COL ", p.get_file(), " meshes=", meshes, " bodies=", kinds, " shapes=", desc)
		n.free()
	quit()
