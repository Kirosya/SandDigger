extends Node
## Small visual/audio bursts that belong to the world, not to one player.
##
## Kept out of SandTerrain and LootManager so those stay pure simulation: they
## emit a signal, and the presentation layer decides what that looks like and
## sounds like on this machine.

const PUFF_SCENE := preload("res://scenes/sand_puff.tscn")


## A shovelful of sand flying out of the hole that was just carved.
func sand_puff(position: Vector3, radius: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var puff := PUFF_SCENE.instantiate() as SandPuff
	if puff == null:
		return
	scene.add_child(puff)
	puff.burst(radius, position + Vector3(0.0, 0.06, 0.0))


## One dig = one puff + one shovel sound, matched by the cut size.
func dig(position: Vector3, radius: float) -> void:
	sand_puff(position, radius)
	Sfx.play_dig(position, radius)
