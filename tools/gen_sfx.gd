extends Node
## Synthesises the game's sound effects into res://assets/audio/*.wav.
##
## Everything is generated from noise and sine waves here instead of being
## downloaded, so the project carries no third-party audio licence and the
## sounds can be re-tuned by editing numbers. Run it headless:
##
##   godot --headless --path . res://tools/gen_sfx.tscn
##
## Then re-import the project so Godot picks up the new .wav files.

const RATE := 22050
const OUT_DIR := "res://assets/audio"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Digging: same recipe, deeper and heavier with each tier.
	_write("dig_soft", _dig(0.165, 2600.0, 150.0, 0.045, 0.72))
	_write("dig_sand", _dig(0.225, 1900.0, 105.0, 0.062, 0.82))
	_write("dig_deep", _dig(0.300, 1400.0, 78.0, 0.085, 0.90))
	_write("dig_massive", _dig(0.380, 1050.0, 58.0, 0.110, 0.95))

	_write("loot_reveal", _loot_reveal())
	_write("pickup", _pickup())
	_write("coin", _coin())
	_write("levelup", _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.115, 0.045))
	_write("upgrade", _upgrade())
	_write("ui_click", _ui_click())
	_write("ui_open", _ui_open())
	_write("denied", _denied())
	_write("step_sand", _step())
	_write("waves", _waves(), true)

	print("SFX DONE")
	get_tree().quit(0)


## --- Sound recipes -------------------------------------------------------

## A shovel bite: filtered noise burst over a low thump. `cutoff` is the
## brightness of the noise, `thump` the pitch of the low body.
func _dig(duration: float, cutoff: float, thump: float, noise_tau: float, gain: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff * 31.0 + thump)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		# Loosen the filter as the bite decays, so it starts crisp and ends dull.
		var open := exp(-t / (noise_tau * 1.6))
		var a := clampf((cutoff * (0.35 + 0.65 * open)) / float(RATE), 0.02, 0.98)
		lp += a * (white - lp)
		var grain := lp * exp(-t / noise_tau)
		var body := sin(TAU * thump * t) * exp(-t / (noise_tau * 1.1)) * 0.55
		var attack := minf(1.0, t / 0.004)
		buf[i] = (grain * 0.85 + body) * attack * gain
	return _normalize(buf, 0.85)


## Something uncovers under the shovel: a short crunch then a bright shimmer.
func _loot_reveal() -> PackedFloat32Array:
	var n := int(0.42 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		lp += 0.22 * (white - lp)
		var crunch := lp * exp(-t / 0.055) * 0.9
		var shimmer := 0.0
		if t > 0.05:
			var st := t - 0.05
			var vibrato := 1.0 + 0.012 * sin(TAU * 6.0 * st)
			shimmer = (sin(TAU * 1318.5 * st * vibrato) + 0.5 * sin(TAU * 1975.5 * st)) \
				* exp(-st / 0.12) * 0.35
		buf[i] = crunch + shimmer
	return _normalize(buf, 0.8)


## Bag it: a quick two-step blip.
func _pickup() -> PackedFloat32Array:
	var n := int(0.17 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		var value := 0.0
		if t < 0.055:
			value = sin(TAU * 660.0 * t) * exp(-t / 0.03)
		elif t >= 0.05:
			var st := t - 0.05
			value = sin(TAU * 990.0 * st) * exp(-st / 0.038)
		buf[i] = value * 0.6
	return _normalize(buf, 0.75)


## Cash register: three metallic pings losing energy.
func _coin() -> PackedFloat32Array:
	var n := int(0.40 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hits := [[0.0, 1.0], [0.075, 0.7], [0.145, 0.45]]
	for i in n:
		var t := float(i) / float(RATE)
		var value := 0.0
		for hit in hits:
			var st: float = t - float(hit[0])
			if st < 0.0:
				continue
			var gain: float = float(hit[1])
			value += (sin(TAU * 1567.98 * st) + 0.6 * sin(TAU * 2093.0 * st)
				+ 0.25 * sin(TAU * 3135.96 * st)) * exp(-st / 0.075) * gain * 0.4
		buf[i] = value
	return _normalize(buf, 0.8)


## Level up: a bright rising arpeggio.
func _arpeggio(notes: Array, note_length: float, overlap: float) -> PackedFloat32Array:
	var total := note_length * (notes.size() - 1) + note_length + 0.25
	var n := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		var value := 0.0
		for index in notes.size():
			var start := note_length * index
			var st := t - start
			if st < 0.0 or st > note_length + overlap:
				continue
			var freq: float = float(notes[index])
			var env := minf(1.0, st / 0.008) * exp(-st / (note_length * 1.4))
			value += (sin(TAU * freq * st) + 0.35 * sin(TAU * freq * 2.0 * st)
				+ 0.12 * sin(TAU * freq * 3.0 * st)) * env * 0.32
		buf[i] = value
	return _normalize(buf, 0.85)


## Bought an upgrade: a rising, slightly wobbly sweep.
func _upgrade() -> PackedFloat32Array:
	var n := int(0.55 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var freq := lerpf(320.0, 1180.0, pow(t / 0.42, 0.7))
		phase += TAU * freq / float(RATE)
		var env := minf(1.0, t / 0.02) * exp(-t / 0.35)
		var wobble := 1.0 + 0.06 * sin(TAU * 11.0 * t)
		buf[i] = (sin(phase) + 0.3 * sin(phase * 2.0)) * env * wobble * 0.45
	return _normalize(buf, 0.85)


func _ui_click() -> PackedFloat32Array:
	var n := int(0.055 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += 0.55 * (rng.randf_range(-1.0, 1.0) - lp)
		var value := lp * exp(-t / 0.008) * 0.7 + sin(TAU * 620.0 * t) * exp(-t / 0.014) * 0.3
		buf[i] = value * minf(1.0, t / 0.002)
	return _normalize(buf, 0.7)


func _ui_open() -> PackedFloat32Array:
	var n := int(0.16 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var freq := lerpf(300.0, 620.0, t / 0.16)
		phase += TAU * freq / float(RATE)
		buf[i] = sin(phase) * minf(1.0, t / 0.01) * exp(-t / 0.11) * 0.55
	return _normalize(buf, 0.7)


## "You can't do that": two descending low blips.
func _denied() -> PackedFloat32Array:
	var n := int(0.22 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		var value := 0.0
		if t < 0.08:
			value = sin(TAU * 330.0 * t) * exp(-t / 0.05)
		elif t >= 0.10:
			var st := t - 0.10
			value = sin(TAU * 220.0 * st) * exp(-st / 0.05)
		buf[i] = value * 0.5
	return _normalize(buf, 0.6)


func _step() -> PackedFloat32Array:
	var n := int(0.13 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += 0.18 * (rng.randf_range(-1.0, 1.0) - lp)
		var value := lp * exp(-t / 0.030) * minf(1.0, t / 0.006)
		buf[i] = value
	return _normalize(buf, 0.5)


## Seamless surf: two layers of filtered noise breathing at different rates.
## The tail is cross-faded into the head so the loop has no click.
func _waves() -> PackedFloat32Array:
	var seconds := 8.0
	var fade := 0.9
	var n := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	var lp_a := 0.0
	var lp_b := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		lp_a += 0.045 * (white - lp_a)
		lp_b += 0.16 * (white - lp_b)
		var swell := 0.45 + 0.30 * sin(TAU * t / 4.0 - PI * 0.5) + 0.12 * sin(TAU * t / 1.7)
		buf[i] = (lp_a * 2.4 * swell + lp_b * 0.55 * swell) * 0.55
	# Cross-fade the last `fade` seconds back over the first ones.
	var fade_n := int(fade * RATE)
	for i in fade_n:
		var k := float(i) / float(fade_n)
		var tail := buf[n - fade_n + i]
		buf[i] = lerpf(tail, buf[i], k)
	buf.resize(n - fade_n)
	return _normalize(buf, 0.55)


## --- Helpers -------------------------------------------------------------

func _normalize(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0001
	for value in buf:
		loudest = maxf(loudest, absf(value))
	var scale := peak / loudest
	for i in buf.size():
		buf[i] = clampf(buf[i] * scale, -1.0, 1.0)
	return buf


func _write(name: String, samples: PackedFloat32Array, looping := false) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	var path := "%s/%s.wav" % [OUT_DIR, name]
	var err := stream.save_to_wav(path)
	print("  %-14s %6.2f s  err=%d" % [name, float(samples.size()) / float(RATE), err])
