extends Node

## Purr-fect Timing: tiny procedural synth on an AudioStreamGenerator.
## Plays a soft cafe metronome (wood-block-ish sine "tocks") at the order's BPM plus short
## chimes for judgements. Fully optional: `enabled = false` = visual-only play.
##
## Sync: every sample written gets a play time on the order clock:
##   t_play = clock.now() + queued_frames / mix_rate + AudioServer output latency
## so beat ticks land on the same analytic beat times the visuals and judging use.

const MIX_RATE := 22050.0
const BUFFER_SEC := 0.1
const MAX_VOICES := 10

var clock: RefCounted = null
var enabled: bool = true:
	set(v):
		enabled = v
		if not v:
			_voices.clear()
			_events.clear()

## Metronome source (set by the game): beat 0 time, period (s), and whether to tick.
var beat_t0: float = 0.0
var beat_period: float = 0.6
var metronome_on: bool = false
var volume: float = 0.5
## 1 = full ticks (beat steps), lower = a soft background pulse (other steps).
var metronome_gain: float = 1.0

var _player: AudioStreamPlayer
var _gen: AudioStreamGenerator
var _pb: AudioStreamGeneratorPlayback
var _voices: Array = []   # {start, freq, dur, amp, decay}
var _events: Array = []   # pending {t, freq, dur, amp, decay}
var _next_beat: int = -1
var _frozen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = MIX_RATE
	_gen.buffer_length = BUFFER_SEC
	_player = AudioStreamPlayer.new()
	_player.name = "PTSynthPlayer"
	_player.stream = _gen
	_player.volume_db = -6.0
	add_child(_player)


func start(p_clock: RefCounted) -> void:
	clock = p_clock
	_voices.clear()
	_events.clear()
	_next_beat = -1
	_frozen = false
	if _player != null and not _player.playing:
		_player.play()
		_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func stop() -> void:
	metronome_on = false
	_voices.clear()
	_events.clear()
	if _player != null and _player.playing:
		_player.stop()
	_pb = null


## Freeze while the order is paused (clock stopped): no new samples, voices dropped.
func set_frozen(on: bool) -> void:
	_frozen = on
	if on:
		_voices.clear()
		_events.clear()
		_next_beat = -1


## Schedule a tone at clock time t (t <= now = as soon as possible).
func tone(t: float, freq: float, dur: float = 0.12, amp: float = 0.25, decay: float = 18.0) -> void:
	if not enabled:
		return
	_events.append({"t": t, "freq": freq, "dur": dur, "amp": amp, "decay": decay})
	_events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))


## Cute judgement chimes (C major pentatonic).
func chime(j: String) -> void:
	if clock == null:
		return
	var t: float = clock.now()
	match j:
		"purrfect":
			tone(t, 1318.5, 0.12, 0.22, 16.0)
			tone(t + 0.07, 1568.0, 0.18, 0.22, 12.0)
		"good":
			tone(t, 1046.5, 0.16, 0.2, 14.0)
		"ok":
			tone(t, 523.25, 0.14, 0.14, 16.0)
		"ding":
			tone(t, 1760.0, 0.3, 0.2, 8.0)
			tone(t + 0.1, 2093.0, 0.35, 0.16, 7.0)
		"puff":
			tone(t, 220.0, 0.2, 0.12, 10.0)


func _process(_delta: float) -> void:
	if _pb == null or clock == null or _frozen:
		return
	var avail: int = _pb.get_frames_available()
	if avail <= 0:
		return
	var queued: float = maxf(0.0, BUFFER_SEC * MIX_RATE - float(avail))
	var t0: float = clock.now() + queued / MIX_RATE + AudioServer.get_output_latency()
	if _next_beat < 0 and beat_period > 0.0:
		_next_beat = maxi(0, ceili((t0 - beat_t0) / beat_period))
	var buf := PackedVector2Array()
	buf.resize(avail)
	var inv_rate: float = 1.0 / MIX_RATE
	for i in avail:
		var t: float = t0 + float(i) * inv_rate
		if enabled and metronome_on and beat_period > 0.0:
			var bt: float = beat_t0 + float(_next_beat) * beat_period
			if t >= bt:
				var down: bool = _next_beat % 4 == 0
				_start_voice(t, 784.0 if down else 587.33, 0.09, (0.16 if down else 0.11) * metronome_gain, 30.0)
				_start_voice(t, 196.0 if down else 147.0, 0.07, 0.08 * metronome_gain, 40.0)
				_next_beat += 1
		elif beat_period > 0.0:
			_next_beat = maxi(_next_beat, ceili((t - beat_t0) / beat_period))
		while not _events.is_empty() and float(_events[0]["t"]) <= t:
			var e: Dictionary = _events.pop_front()
			_start_voice(t, float(e["freq"]), float(e["dur"]), float(e["amp"]), float(e["decay"]))
		var s: float = 0.0
		var vi: int = _voices.size() - 1
		while vi >= 0:
			var v: Dictionary = _voices[vi]
			var age: float = t - float(v["start"])
			if age > float(v["dur"]) * 3.0:
				_voices.remove_at(vi)
			else:
				var env: float = minf(1.0, age / 0.004) * exp(-age * float(v["decay"]))
				s += sin(TAU * float(v["freq"]) * age) * float(v["amp"]) * env
			vi -= 1
		s = tanh(s * volume * 1.4)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)


func _start_voice(t: float, freq: float, dur: float, amp: float, decay: float) -> void:
	if _voices.size() >= MAX_VOICES:
		_voices.pop_front()
	_voices.append({"start": t, "freq": freq, "dur": dur, "amp": amp, "decay": decay})
