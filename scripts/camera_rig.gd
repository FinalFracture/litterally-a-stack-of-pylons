extends Node3D

const BOOM_BASE := 2.4
const BOOM_PER_M := 0.55
const LOOK_BIAS := 0.08
const SPRING_MARGIN := 0.3
## Closest the lens may sit. Still on the boom; never through the player.
const MIN_ARM := 0.45
## Layer 1 is terrain and the world. Layer 3 is city curbs. Both block the camera.
const COLLIDE_MASK := 1 | 4
const MOUSE_SENS := 0.003
const PITCH_MIN := 0.15
const PITCH_MAX := 1.2
# Keyboard look (only with PYLONS_KEYMOUSE=1 or --keymouse), radians per second.
const KEY_YAW_SPEED := 2.2
const KEY_PITCH_SPEED := 1.3

@export var target_path: NodePath

var _target: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := atan(1.25 / 2.4)
var _spring_shape: SphereShape3D
var _spring_query: PhysicsShapeQueryParameters3D
var _debug_on := false
var _debug_layer: CanvasLayer
var _debug_label: Label


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_camera = get_node_or_null("Camera3D") as Camera3D
	_spring_shape = SphereShape3D.new()
	_spring_shape.margin = 0.0
	_spring_query = PhysicsShapeQueryParameters3D.new()
	_spring_query.shape = _spring_shape
	_spring_query.collide_with_areas = false
	_spring_query.collide_with_bodies = true
	_spring_query.collision_mask = COLLIDE_MASK
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_place()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_toggle_debug()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Mouse right turns the view right. Mouse up still looks up.
		_yaw -= motion.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch + motion.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)


func _physics_process(_delta: float) -> void:
	_place()


func _process(delta: float) -> void:
	if LaunchConfig.keymouse_on() and not get_tree().paused:
		_key_look(delta)
	_place()
	_refresh_debug()


func _key_look(delta: float) -> void:
	# Same sense as the mouse: right turns the view right, up looks up.
	var turn := Input.get_axis("km_look_left", "km_look_right")
	var tilt := Input.get_axis("km_look_down", "km_look_up")
	_yaw -= turn * KEY_YAW_SPEED * delta
	_pitch = clampf(_pitch + tilt * KEY_PITCH_SPEED * delta, PITCH_MIN, PITCH_MAX)


func snap() -> void:
	_place()


func look_toward(at: Vector3) -> void:
	if _target == null:
		return
	var from := _target.global_position
	var flat := Vector2(from.x - at.x, from.z - at.z)
	if flat.length_squared() < 0.04:
		return
	flat = flat.normalized()
	_yaw = atan2(flat.x, flat.y)
	_pitch = 0.42
	_place()


func _column_height() -> float:
	if _target != null:
		var stack := _target.get_node_or_null("StackController")
		if stack != null and stack.has_method("get_stack_height"):
			return float(stack.get_stack_height())
	return GameConstants.STANDARD_H


func _place() -> void:
	if _target == null or _camera == null:
		return
	var column_h := _column_height()
	var look := _target.global_position + Vector3(0.0, column_h * 0.5 + LOOK_BIAS, 0.0)
	var boom := BOOM_BASE + BOOM_PER_M * column_h
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * boom
	var desired := look + offset
	var cam_pos := desired
	if not _hit_camera():
		cam_pos = _spring(look, desired)
	if cam_pos.distance_squared_to(look) < 0.04:
		cam_pos = look + offset.normalized() * 0.4
	cam_pos = _above_drawn(cam_pos)
	global_position = cam_pos
	_camera.position = Vector3.ZERO
	_camera.look_at(look, Vector3.UP)


## Keep the lens above the drawn ground. Collision can sit under a simplified
## triangle; the near plane would then look out through the floor into the sky.
func _above_drawn(cam_pos: Vector3) -> Vector3:
	var world := get_parent()
	if world == null:
		return cam_pos
	var gen: Object = world.get("generator")
	if gen == null or not gen.has_method("drawn_height_at"):
		return cam_pos
	var floor_y := float(gen.call("drawn_height_at", cam_pos.x, cam_pos.z))
	if floor_y < -70.0:
		return cam_pos
	var min_y := floor_y + 0.3
	if cam_pos.y < min_y:
		cam_pos.y = min_y
	return cam_pos


func _hit_camera() -> bool:
	if _target != null and _target.get("ragdoll") == true:
		return true
	var tree := get_tree()
	if tree == null:
		return false
	return tree.get_first_node_in_group("hit_tumble") != null


## Shorten the boom along look→desired only. The ray starts at the player centre.
## The result never crosses `look`, so a wall cannot flip the camera 180°.
func _spring(look: Vector3, desired: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return desired
	var to_cam := desired - look
	var full := to_cam.length()
	if full < 0.0001:
		return desired
	var dir := to_cam / full
	var radius := _spring_radius()
	var space := world.direct_space_state
	var exclude := _spring_exclude()
	var query := PhysicsRayQueryParameters3D.create(look, desired)
	query.collide_with_areas = false
	query.collision_mask = COLLIDE_MASK
	query.exclude = exclude
	query.hit_from_inside = true
	var limit := full
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		limit = clampf(look.distance_to(hit.position) - SPRING_MARGIN, MIN_ARM, full)
	if _sphere_blocked(space, look + dir * limit, radius, exclude):
		var lo := MIN_ARM
		var hi := limit
		if not _sphere_blocked(space, look + dir * lo, radius, exclude):
			for _i in 6:
				var mid := (lo + hi) * 0.5
				if _sphere_blocked(space, look + dir * mid, radius, exclude):
					hi = mid
				else:
					lo = mid
			limit = lo
		else:
			limit = MIN_ARM
	return look + dir * limit


func _spring_radius() -> float:
	var near := 0.05
	if _camera != null:
		near = _camera.near
	return maxf(SPRING_MARGIN, near + 0.2)


func _spring_exclude() -> Array[RID]:
	var exclude: Array[RID] = []
	if _target is CollisionObject3D:
		exclude.append((_target as CollisionObject3D).get_rid())
	return exclude


func _sphere_blocked(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float, exclude: Array[RID]) -> bool:
	_spring_shape.radius = radius
	_spring_query.transform = Transform3D(Basis.IDENTITY, at)
	_spring_query.exclude = exclude
	return not space.intersect_shape(_spring_query, 1).is_empty()


## Look point buried in a heightfield: step through the player until the sphere is in open air.
func _walk_clear(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, radius: float, exclude: Array[RID]) -> Vector3:
	var pos := from
	for i in 16:
		pos = from + dir * (radius * 0.5 * float(i + 1))
		if not _sphere_blocked(space, pos, radius, exclude):
			return pos
	return pos


## A steep face needs the near plane in front of the rock, not buried in the collision volume.
func _clear_steep_face(space: PhysicsDirectSpaceState3D, pos: Vector3, dir: Vector3, radius: float, exclude: Array[RID]) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(pos, pos + dir * (radius + 0.2))
	query.collide_with_areas = false
	query.collision_mask = COLLIDE_MASK
	query.exclude = exclude
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return pos
	var normal: Vector3 = hit.normal
	if normal.y >= 0.75:
		return pos
	var extra := radius
	var nudged := pos + normal * extra
	if _sphere_blocked(space, nudged, radius, exclude):
		return pos
	return nudged


func _toggle_debug() -> void:
	_debug_on = not _debug_on
	if _debug_layer == null:
		_debug_layer = CanvasLayer.new()
		_debug_layer.layer = 30
		add_child(_debug_layer)
		_debug_label = Label.new()
		_debug_label.position = Vector2(12, 12)
		_debug_label.add_theme_font_size_override("font_size", 16)
		_debug_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		_debug_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		_debug_label.add_theme_constant_override("outline_size", 4)
		_debug_layer.add_child(_debug_label)
	_debug_layer.visible = _debug_on


func _refresh_debug() -> void:
	if not _debug_on or _debug_label == null or _camera == null:
		return
	var parts := get_tree().get_nodes_in_group("terrain_mesh").size()
	var p := global_position
	_debug_label.text = "cam %.2f, %.2f, %.2f\nnear %.3f\nterrain_mesh %d" % [p.x, p.y, p.z, _camera.near, parts]
