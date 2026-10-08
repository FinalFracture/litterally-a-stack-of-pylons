extends RefCounted

static var _engine: AudioStreamWAV
static var _siren: AudioStreamWAV
static var _music: AudioStreamWAV


static func engine() -> AudioStreamWAV:
	if _engine == null:
		_engine = _wav(_hum(0.45, 22050), 22050)
	return _engine


static func siren() -> AudioStreamWAV:
	if _siren == null:
		_siren = _wav(_two_tone(640.0, 780.0, 0.42, 22050), 22050)
	return _siren


static func music() -> AudioStreamWAV:
	if _music == null:
		var notes: Array[float] = [329.6, 293.7, 261.6, 293.7, 329.6, 392.0, 329.6, 293.7, 261.6, 293.7, 329.6, 392.0, 440.0, 392.0, 329.6, 293.7]
		_music = _wav(_phrase(notes, 0.5, 22050), 22050)
	return _music


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = data.size() / 2
	wav.data = data
	return wav


static func _phrase(freqs: Array[float], note_sec: float, rate: int) -> PackedByteArray:
	var frames: int = int(note_sec * float(rate))
	var data := PackedByteArray()
	data.resize(frames * freqs.size() * 2)
	var cursor := 0
	for freq in freqs:
		for n in frames:
			var t: float = float(n) / float(rate)
			var env := 1.0
			if n < 180:
				env = float(n) / 180.0
			elif n > frames - 500:
				env = float(frames - n) / 500.0
			var s: float = sin(TAU * freq * t) * 0.18 * env
			s += sin(TAU * freq * 2.0 * t) * 0.03 * env
			cursor = _write(data, cursor, s)
	return data


static func _hum(seconds: float, rate: int) -> PackedByteArray:
	var frames: int = int(seconds * float(rate))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var cursor := 0
	for n in frames:
		var t: float = float(n) / float(rate)
		var s: float = sin(TAU * 62.0 * t) * 0.16
		s += sin(TAU * 93.0 * t) * 0.07
		s += sin(TAU * 31.0 * t) * 0.05
		cursor = _write(data, cursor, s)
	return data


static func _two_tone(a: float, b: float, half: float, rate: int) -> PackedByteArray:
	var frames: int = int(half * float(rate))
	var data := PackedByteArray()
	data.resize(frames * 4)
	var cursor := 0
	for n in frames * 2:
		var freq: float = a if n < frames else b
		var t: float = float(n) / float(rate)
		var s: float = sin(TAU * freq * t) * 0.2
		cursor = _write(data, cursor, s)
	return data


static func _write(data: PackedByteArray, cursor: int, sample: float) -> int:
	var v: int = int(clampf(sample, -1.0, 1.0) * 28000.0)
	data[cursor] = v & 255
	data[cursor + 1] = (v >> 8) & 255
	return cursor + 2
