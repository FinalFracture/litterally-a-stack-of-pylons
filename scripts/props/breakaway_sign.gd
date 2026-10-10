extends RigidBody3D
## Breakaway sign post (Asset Manager PROPOSAL, CE call 2026-10-09: signs are knockable; the Developer owns wiring).
## The post is FROZEN (acts static: cones, pedestrians and slow pushes stop against it) until a body that is fast
## and heavy enough enters HitZone (a slightly larger Area3D around the lower post). Then it unfreezes, gets an
## impulse along the hitter's travel direction and falls as a normal RigidBody. The 0.1 m base stub stays (no collision).
signal knocked_down(by: Node3D)
@export var min_speed := 1.5         ## m/s; below this nothing breaks
@export var min_momentum := 300.0    ## kg*m/s (e.g. 1,500 kg car at 0.2 m/s would NOT break: speed gate first)
@export var impulse_scale := 1.1     ## x post mass x hitter speed
@export var default_mass_kg := 80.0  ## used for bodies without mass (CharacterBody3D)
var broken := false

func _ready() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	$HitZone.body_entered.connect(_on_hit)

func _vel(b: Node) -> Vector3:
	if b is RigidBody3D: return b.linear_velocity
	if b is CharacterBody3D: return b.velocity
	return Vector3.ZERO

func _on_hit(b: Node3D) -> void:
	if broken or b == self: return
	var v := _vel(b); var s := v.length()
	var m: float = b.mass if b is RigidBody3D else default_mass_kg
	if s < min_speed or s * m < min_momentum: return
	broken = true
	freeze = false
	$HitZone.set_deferred("monitoring", false)
	var dir := Vector3(v.x, 0.0, v.z).normalized()
	apply_impulse(dir * s * mass * impulse_scale + Vector3.UP * mass * 0.3, Vector3(0, 0.6, 0))
	knocked_down.emit(b)
