class_name SandPuff
extends GPUParticles3D
## A short burst of sand thrown up by one dig.
##
## Kept as a tiny self-deleting scene: the dig rate is at most a handful per
## second, so spawning one per dig is cheaper than maintaining a pool of
## GPUParticles3D nodes that all need resetting.

func _ready() -> void:
	emitting = false


## Fires the burst for a cut of `radius` metres, then removes itself.
func burst(radius: float, at: Vector3) -> void:
	global_position = at
	# 0 for the teaspoon, 1 for the earth shovel and up, so the four biggest
	# tiers all throw the maximum spray.
	var t := clampf((radius - 0.10) / 0.60, 0.0, 1.0)
	self.amount = clampi(int(lerpf(20.0, 64.0, t)), 18, 72)

	var material := process_material as ParticleProcessMaterial
	if material != null:
		# A wider cut throws more sand, further and in bigger clumps.
		material.initial_velocity_min = lerpf(0.9, 1.8, t)
		material.initial_velocity_max = lerpf(2.4, 4.4, t)
		material.scale_min = lerpf(0.5, 0.9, t)
		material.scale_max = lerpf(1.0, 1.9, t)

	restart()
	await get_tree().create_timer(lifetime + 0.35).timeout
	queue_free()
