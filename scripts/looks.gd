class_name Looks
extends RefCounted
## Procedural materials built from noise, so the arena and the fighters get
## a worn, grimy look without shipping any texture files.

static var _cache := {}


## A noise-textured surface. dark/light are the two ends of the colour ramp.
static func surface(key: String, dark: Color, light: Color, frequency: float,
		roughness := 0.9, uv_scale := 1.0, world := false, metallic := 0.0,
		bump := 3.0, cellular := false) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_texture(hash(key), frequency, dark, light, false, bump, cellular)
	mat.normal_enabled = true
	mat.normal_texture = _noise_texture(hash(key) + 17, frequency * 1.7, dark, light, true, bump, cellular)
	mat.normal_scale = 0.7
	mat.roughness = roughness
	mat.metallic = metallic
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = world
	mat.uv1_scale = Vector3.ONE * uv_scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat


static func dirt() -> StandardMaterial3D:
	return surface("dirt", Color(0.2, 0.15, 0.1), Color(0.46, 0.37, 0.26), 0.012, 1.0, 0.18, true, 0.0, 6.0)


static func wood() -> StandardMaterial3D:
	var mat := surface("wood", Color(0.17, 0.11, 0.07), Color(0.42, 0.3, 0.19), 0.02, 0.85, 1.2, false, 0.0, 5.0)
	return mat


static func straw() -> StandardMaterial3D:
	return surface("straw", Color(0.45, 0.36, 0.17), Color(0.78, 0.66, 0.38), 0.05, 1.0, 1.5, false, 0.0, 6.0)


static func steel() -> StandardMaterial3D:
	return surface("steel", Color(0.38, 0.39, 0.4), Color(0.62, 0.63, 0.64), 0.03, 0.38, 2.0, false, 0.85, 1.5)


## Linen, wool, leather and skin: fine-grained noise tinted around color.
static func cloth(color: Color, roughness := 0.95, grain := 0.08) -> StandardMaterial3D:
	return surface("cloth_%s_%.2f" % [color.to_html(false), roughness],
			color.darkened(0.3), color.lightened(0.08), grain, roughness, 3.0, false, 0.0, 2.5)


static func skin(color: Color) -> StandardMaterial3D:
	return surface("skin_%s" % color.to_html(false), color.darkened(0.12), color.lightened(0.05),
			0.04, 0.7, 2.0, false, 0.0, 0.8)


static func _noise_texture(seed_value: int, frequency: float, dark: Color, light: Color,
		normal: bool, bump: float, cellular: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 5
	if cellular:
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	if normal:
		tex.as_normal_map = true
		tex.bump_strength = bump
	else:
		var ramp := Gradient.new()
		ramp.set_color(0, dark)
		ramp.set_color(1, light)
		tex.color_ramp = ramp
	return tex
