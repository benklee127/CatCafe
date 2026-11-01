extends Node2D

# One drawable piece of the procedural Cat2D rig (body, head, ear, leg, tail...).
# Holds no art itself: _draw() calls back into the owning Cat2D, which knows
# the genome palette. Redraws only when queue_redraw() is called (genome change,
# leg length change, eye open/close), except the tail which Cat2D redraws each
# frame because its ripple bends the shape.

var rig: Node = null
var kind: StringName = &""
var params: Dictionary = {}

func setup(owner_rig: Node, part_kind: StringName, part_params: Dictionary = {}) -> void:
	rig = owner_rig
	kind = part_kind
	params = part_params

func _draw() -> void:
	if rig != null and is_instance_valid(rig) and rig.has_method("_draw_part"):
		rig._draw_part(self, kind, params)
