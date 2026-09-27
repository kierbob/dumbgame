class_name Sfx
extends RefCounted
## Impact sounds synthesised at startup: a ringing steel clang, a wet cut and
## a dull body thud. Each is rendered once into a 16-bit wave and cached.

const RATE := 22050

static var _cache := {}


static func clang() -> AudioStreamWAV:
	if not _cache.has("clang"):
		# Inharmonic partials with different decay rates read as struck steel.
		var partials := [[587.0, 1.0, 5.0], [1419.0, 0.6, 7.5], [2263.0, 0.45, 10.0],
				[3175.0, 0.3, 13.0], [4402.0, 0.2, 18.0]]
		var n := int(RATE * 1.0)
		var s := PackedFloat32Array()
		s.resize(n)
		for i in n:
			var t := float(i) / RATE
			var v := 0.0
			for p: Array in partials:
				v += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
			v += (randf() * 2.0 - 1.0) * exp(-t * 120.0) * 0.6
			s[i] = v * 0.3
		_cache["clang"] = _wav(s)
	return _cache["clang"]


static func cut() -> AudioStreamWAV:
	if not _cache.has("cut"):
		var n := int(RATE * 0.3)
		var s := PackedFloat32Array()
		s.resize(n)
		var lp := 0.0
		for i in n:
			var t := float(i) / RATE
			var noise := randf() * 2.0 - 1.0
			lp += (noise - lp) * lerpf(0.5, 0.08, clampf(t / 0.2, 0.0, 1.0))
			var thump := sin(TAU * 85.0 * t) * exp(-t * 28.0)
			s[i] = (lp * exp(-t * 16.0) * 0.9 + thump * 0.7) * 0.6
		_cache["cut"] = _wav(s)
	return _cache["cut"]


static func thud() -> AudioStreamWAV:
	if not _cache.has("thud"):
		var n := int(RATE * 0.35)
		var s := PackedFloat32Array()
		s.resize(n)
		var lp := 0.0
		for i in n:
			var t := float(i) / RATE
			lp += (randf() * 2.0 - 1.0 - lp) * 0.06
			s[i] = (sin(TAU * 58.0 * t) * exp(-t * 13.0) + lp * exp(-t * 25.0) * 1.5) * 0.55
		_cache["thud"] = _wav(s)
	return _cache["thud"]


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
