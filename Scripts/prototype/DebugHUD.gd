extends CanvasLayer

var label: Label

func _ready() -> void:
	label = Label.new()
	label.position = Vector2(16, 12)
	label.size = Vector2(760, 520)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)

func render_debug(cats: Array, patrons: Array) -> void:
	var lines: Array[String] = []
	lines.append("CAT CAFE DEBUG HUD")
	lines.append("Cats: %d | Patrons: %d" % [cats.size(), patrons.size()])
	for c in cats:
		lines.append("%s | overstim %.1f | state %s" % [c.name, c.overstim, _state_name(c.state)])
	label.text = "\n".join(lines)

func _state_name(state_value: int) -> String:
	match state_value:
		0:
			return "WANDER"
		1:
			return "RETREAT"
		2:
			return "REST"
		_:
			return "UNKNOWN"
