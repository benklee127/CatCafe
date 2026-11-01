extends RefCounted

## Purr-fect Timing order clock (seconds, float).
## Real mode reads Time.get_ticks_usec() directly, so judging never depends on frame rate:
## input handlers stamp events with now() at dispatch time and every target time is analytic.
## Manual mode (probe / capture tools) uses manual_t, advanced by the caller.
## pause()/resume() freeze the clock (Esc pause, parked orders) without losing progress.

var manual: bool = false
var manual_t: float = 0.0
var _base_usec: int = 0
var _paused: bool = false
var _paused_at: float = 0.0


func _init(p_manual: bool = false) -> void:
	manual = p_manual
	reset()


func reset() -> void:
	_base_usec = Time.get_ticks_usec()
	manual_t = 0.0
	_paused = false
	_paused_at = 0.0


func raw_now() -> float:
	if manual:
		return manual_t
	return float(Time.get_ticks_usec() - _base_usec) / 1000000.0


func now() -> float:
	return _paused_at if _paused else raw_now()


func is_paused() -> bool:
	return _paused


func pause() -> void:
	if _paused:
		return
	_paused_at = raw_now()
	_paused = true


func resume() -> void:
	if not _paused:
		return
	if manual:
		manual_t = _paused_at
	else:
		_base_usec += int(roundf((raw_now() - _paused_at) * 1000000.0))
	_paused = false
