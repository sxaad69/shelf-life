class_name GameAudio
extends Node

## Procedural WebAudio-style SFX via AudioStreamGenerator-free approach:
## pre-rendered at boot into AudioStreamWAV buffers (jsfxr-style synthesis,
## zero asset downloads; OGG files in assets/audio are the SAME recipes
## rendered offline for the release build — this node is the fallback and
## the web-build source of truth).

var _streams := {}   # name -> AudioStreamWAV


func _ready() -> void:
	_streams["thock"] = _render_thock()
	_streams["chime"] = _render_chime()
	_streams["buzz"] = _render_buzz()
	_streams["bell"] = _render_bell()
	_streams["ping"] = _render_ping()


func play(sfx_name: String, volume_db: float = -6.0) -> void:
	if not _streams.has(sfx_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[sfx_name]
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play_chime_ok() -> void:
	play("chime", -4.0)


# ------------------------------------------------------------------
# Synthesis helpers (16-bit mono 22050 Hz)
# ------------------------------------------------------------------
const RATE := 22050


func _buf(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: float = clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	wav.data = bytes
	return wav


func _env(i: int, n: int, attack: float = 0.005) -> float:
	var t := float(i) / n
	var a := minf(float(i) / maxf(attack * n, 1.0), 1.0)
	return a * pow(1.0 - t, 2.0)


func _render_thock() -> AudioStreamWAV:
	# Wooden place-thock: decaying sine burst + click transient.
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var f := 190.0 + 120.0 * exp(-t * 60.0)
		var v := 0.6 * sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.7 * t)
		if i < 40:
			v += (1.0 - float(i) / 40.0) * 0.5 * (randf() * 2.0 - 1.0)
		s[i] = v * _env(i, n, 0.001)
	return _buf(s)


func _render_chime() -> AudioStreamWAV:
	# Two-note rising badge chime (E5->B5-ish triangle).
	var n := int(RATE * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var note := 659.0 if t < 0.12 else 988.0
		var lt := t if t < 0.12 else t - 0.12
		var v := 0.4 * sin(TAU * note * t) + 0.15 * sin(TAU * note * 2.0 * t)
		var env := minf(lt / 0.004, 1.0) * exp(-lt * 9.0)
		s[i] = v * env
	return _buf(s)


func _render_buzz() -> AudioStreamWAV:
	# Violation buzz: low square wobble.
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var f := 150.0 + 20.0 * sin(TAU * 9.0 * t)
		var sq := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
		s[i] = 0.22 * sq * _env(i, n, 0.01)
	return _buf(s)


func _render_bell() -> AudioStreamWAV:
	# OPEN SHOP bell: struck bell partials.
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.5 * sin(TAU * 880.0 * t) + 0.3 * sin(TAU * 1320.0 * t) \
				+ 0.18 * sin(TAU * 2093.0 * t) * exp(-t * 6.0)
		s[i] = v * minf(t / 0.002, 1.0) * exp(-t * 3.5)
	return _buf(s)


func _render_ping() -> AudioStreamWAV:
	# Hint ping: soft high blip.
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		s[i] = 0.35 * sin(TAU * 1245.0 * t) * _env(i, n, 0.003)
	return _buf(s)


func make_loop_stream() -> AudioStreamWAV:
	# Mellow shop loop ~8s: slow chord pad (A minor add9), seamless loop.
	var dur := 8.0
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var freqs := [220.0, 261.63, 329.63, 493.88]
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		for fi in range(freqs.size()):
			var f: float = freqs[fi]
			var wob := 0.5 + 0.5 * sin(TAU * (0.11 + fi * 0.03) * t)
			v += 0.05 * sin(TAU * f * t + fi) * wob
			v += 0.02 * sin(TAU * f * 2.0 * t) * wob
		s[i] = v
	# crossfade tail into head for seamless looping
	var xf := int(RATE * 0.5)
	for i in range(xf):
		var blend := float(i) / xf
		s[i] = s[i] * blend + s[n - xf + i] * (1.0 - blend)
	var out := PackedFloat32Array()
	out.resize(n - xf)
	for i in range(n - xf):
		out[i] = s[i]
	var wav := _buf(out)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = (n - xf)
	return wav
