class_name VfxEffect
extends Node3D
## Copy-in VFX wrapper (Asset Manager, in-house, CC0-compatible).
## One-shot effects: call play(strength). Continuous effects (tire smoke, scrape sparks): call set_active(true/false).
## Works with GPUParticles3D or CPUParticles3D children (the *_cpu.tscn Quest fallbacks use the same script).
## An optional child AudioStreamPlayer3D named "Sfx" plays the paired sound.

@export var continuous := false
@export var auto_free := false      ## free the node after the longest lifetime (one-shots spawned at runtime)
@export var play_on_ready := false
@export var sfx_volume_db := 0.0

func _ready() -> void:
	if play_on_ready:
		if continuous: set_active(true)
		else: play()

func play(strength: float = 1.0) -> void:
	for p in particles():
		p.restart()
		p.emitting = true
	var s := get_node_or_null("Sfx") as AudioStreamPlayer3D
	if s and s.stream:
		s.volume_db = sfx_volume_db + linear_to_db(clampf(strength, 0.05, 1.0))
		s.play()
	if auto_free and not continuous:
		get_tree().create_timer(max_lifetime() + 0.25, false).timeout.connect(queue_free)

func set_active(on: bool) -> void:
	for p in particles():
		p.emitting = on
	var s := get_node_or_null("Sfx") as AudioStreamPlayer3D
	if s and s.stream:
		if on and not s.playing: s.play()
		elif not on and s.playing: s.stop()

func particles() -> Array:
	var out := []
	for c in get_children():
		if c is GPUParticles3D or c is CPUParticles3D: out.append(c)
	return out

func max_lifetime() -> float:
	var m := 0.0
	for p in particles():
		m = maxf(m, p.lifetime / maxf(p.speed_scale, 0.001))
	return m
