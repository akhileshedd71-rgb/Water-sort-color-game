class_name SoundBank
extends Node
## Small original synthesized water/pluck cues, cached as offline PCM WAV samples.

@export var enabled: bool = true
const SAMPLE_RATE: int = 22050
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _cursor: int = 0

func _ready() -> void:
	for i in range(6):
		var player := AudioStreamPlayer.new()
		player.volume_db = -9.0
		add_child(player)
		_players.append(player)
	for event in ["select", "pour", "complete", "win", "undo", "invalid", "click"]:
		_streams[event] = _synthesize(event)

func play(event: String) -> void:
	if not enabled or _players.is_empty() or not _streams.has(event):
		return
	var player: AudioStreamPlayer = _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	player.stream = _streams[event]
	player.play()

func _synthesize(event: String) -> AudioStreamWAV:
	var duration: float = 0.21
	var notes: Array[float] = [659.25]
	var spacing: float = 0.09
	match event:
		"click":
			duration = 0.10
			notes = [523.25]
		"select":
			duration = 0.18
			notes = [783.99]
		"pour":
			duration = 0.62
			notes = [523.25, 659.25, 783.99, 1046.50, 783.99]
			spacing = 0.085
		"complete":
			duration = 0.65
			notes = [659.25, 783.99, 1046.50]
			spacing = 0.12
		"win":
			duration = 1.08
			notes = [523.25, 659.25, 783.99, 1046.50, 1318.51]
			spacing = 0.14
		"undo":
			duration = 0.27
			notes = [659.25, 523.25]
			spacing = 0.085
		"invalid":
			duration = 0.18
			notes = [220.0, 261.63]
			spacing = 0.0
	var count: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var sample: float = 0.0
		for j in range(notes.size()):
			var age: float = t - float(j) * spacing
			if age < 0.0:
				continue
			var decay: float = 12.0 if event == "pour" else 9.0
			var envelope: float = minf(age / 0.008, 1.0) * exp(-age * decay)
			var frequency: float = notes[j]
			# A tiny downwards chirp sounds like a drop hitting a glass surface.
			var phase: float = TAU * frequency * age + 2.0 * (1.0 - exp(-age * 24.0))
			var tone: float = sin(phase) * 0.75 + sin(phase * 2.0) * 0.17 + sin(phase * 3.0) * 0.05
			sample += tone * envelope * 0.40
		var fade_out: float = clampf((duration - t) / 0.028, 0.0, 1.0)
		var pcm: int = int(clampf(sample * fade_out, -0.95, 0.95) * 32767.0)
		data.encode_s16(i * 2, pcm)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
