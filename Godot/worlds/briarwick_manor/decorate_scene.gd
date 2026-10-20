extends RefCounted
## Authoring helper: saves the embellishments as ordinary editable scene nodes.
const BASE := "res://worlds/briarwick_manor/"
var b: SceneTree
var root: Node3D
var brass: StandardMaterial3D
var flame: ShaderMaterial

func node(title: String, parent: Node, pos := Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	b.add(result, parent, title)
	result.position = pos
	return result

func material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.55
	return result

func mesh(title: String, shape: Mesh, mat: Material, parent: Node3D, pos: Vector3, static_gi := true) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = shape
	result.material_override = mat
	result.gi_mode = GeometryInstance3D.GI_MODE_STATIC if static_gi else GeometryInstance3D.GI_MODE_DISABLED
	b.add(result, parent, title)
	result.position = pos
	return result

func sphere(radius: float) -> SphereMesh:
	var result := SphereMesh.new()
	result.radius = radius
	result.height = radius * 2
	result.radial_segments = 24
	result.rings = 12
	result.add_uv2 = true
	return result

func plaque(parent: Node3D, pos: Vector3, title: String, width := 0.36) -> void:
	b.box("BrassPlate", pos, Vector3(width, 0.012, 0.14), brass, parent)
	var text := Label3D.new()
	b.add(text, parent, "Engraving")
	text.position = pos + Vector3(0, 0.008, 0)
	text.rotation_degrees.x = -90
	text.text = title + "\nF  /  B·Y"
	text.font_size = 30
	text.pixel_size = 0.0009
	text.modulate = Color("291f19")
	text.outline_size = 0
	text.no_depth_test = false
	text.shaded = true

func interact(object: Node3D, action: int, touch: Vector3, active := true) -> void:
	b.mark("TouchPoint", touch, object)
	object.add_to_group("briarwick_interactable", true)
	object.set_script(load(BASE + "manor_interactable.gd"))
	object.action = action
	object.active = active

func particles(title: String, parent: Node3D, smoke: bool) -> void:
	var emitter := CPUParticles3D.new()
	b.add(emitter, parent, title)
	emitter.position = Vector3(0, 0.48, 0)
	emitter.amount = 12 if smoke else 4
	emitter.lifetime = 2.2 if smoke else 1.0
	emitter.one_shot = smoke
	emitter.emitting = not smoke
	emitter.explosiveness = 0.5 if smoke else 0.0
	emitter.direction = Vector3.UP
	emitter.spread = 18
	emitter.gravity = Vector3(0.025, 0.015, 0)
	emitter.initial_velocity_min = 0.04
	emitter.initial_velocity_max = 0.13
	emitter.scale_amount_min = 0.025 if smoke else 0.006
	emitter.scale_amount_max = 0.045 if smoke else 0.012
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.emission_box_extents = Vector3(0.17, 0, 0)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.6, 0.62, 0.66, 0.20) if smoke else Color(1, 0.65, 0.2, 0.6), Color(0.5, 0.5, 0.5, 0)])
	emitter.color_ramp = gradient
	var mat := material(Color.WHITE)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shape := sphere(0.5)
	shape.material = mat
	emitter.mesh = shape
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func candle(candlestick: Node3D) -> void:
	var flames := node("Flames", candlestick)
	for x in [-0.169, 0.0, 0.169]:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.06, 0.12)
		var fire := mesh("Flame", quad, flame, flames, Vector3(x, 0.394 if x != 0 else 0.515, 0), false)
		fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	b.add(light, candlestick, "Glow")
	light.position.y = 0.57
	light.light_color = Color(1, 0.59, 0.24)
	light.light_energy = 0.55
	light.omni_range = 2.3
	light.light_bake_mode = Light3D.BAKE_DISABLED
	particles("Smoke", candlestick, true)
	particles("Sparks", candlestick, false)
	plaque(candlestick, Vector3(0, 0.003, 0.23), "SNUFF / LIGHT")
	interact(candlestick, 0, Vector3(0, 0.3, 0))

func window(frame: Node3D) -> void:
	var detail := node("WindowDressing", frame.get_parent(), frame.position)
	detail.rotation = frame.rotation
	# Frame is a scaled kit instance; dressing is authored in world metre units.
	var pane := QuadMesh.new()
	pane.size = Vector2(1.64, 2.42)
	var glass := ShaderMaterial.new()
	glass.shader = load(BASE + "window_glass.gdshader")
	var glazing := mesh("LeadedRainGlass", pane, glass, detail, Vector3(0, 2.8, 0.075), false)
	glazing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.box("CurtainRail", Vector3(0, 4.19, 0.59), Vector3(2.65, 0.035, 0.035), brass, detail)
	for side in [-1, 1]:
		mesh("Finial", sphere(0.065), brass, detail, Vector3(side * 1.35, 4.19, 0.59))
		var cloth := ShaderMaterial.new()
		cloth.shader = load(BASE + "drapery.gdshader")
		var quad := QuadMesh.new()
		quad.size = Vector2(0.65, 2.87)
		quad.subdivide_width = 24
		quad.subdivide_depth = 24
		var curtain := mesh("LeftCurtain" if side < 0 else "RightCurtain", quad, cloth, detail, Vector3(side * 1.02, 2.69, 0.59), false)
		curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cord and plate sit at hand height, well inside the window collision plane.
	b.box("PullCord", Vector3(1.19, 2.65, 0.73), Vector3(0.016, 2.8, 0.016), brass, detail)
	mesh("CordTassel", sphere(0.075), brass, detail, Vector3(1.19, 1.27, 0.73))
	plaque(detail, Vector3(1.19, 1.13, 0.76), "DRAW CURTAINS", 0.4)
	interact(detail, 1, Vector3(1.19, 1.35, 0.75), false)

func orrery(parent: Node3D) -> void:
	var instrument := node("ClockworkOrrery", parent, Vector3(5, 0.86, -4))
	var base := CylinderMesh.new()
	base.top_radius = 0.42
	base.bottom_radius = 0.46
	base.height = 0.09
	base.add_uv2 = true
	mesh("Pedestal", base, brass, instrument, Vector3(0, 0.045, 0))
	var stem := CylinderMesh.new()
	stem.top_radius = 0.025
	stem.bottom_radius = 0.025
	stem.height = 0.55
	stem.add_uv2 = true
	mesh("Axle", stem, brass, instrument, Vector3(0, 0.32, 0))
	mesh("Sun", sphere(0.10), material(Color("d7a14b"), 0.5), instrument, Vector3(0, 0.57, 0))
	var orbits := node("Orbits", instrument, Vector3(0, 0.4, 0))
	for i in range(3):
		var radius := 0.19 + i * 0.09
		var ring := TorusMesh.new()
		ring.inner_radius = radius - 0.007
		ring.outer_radius = radius + 0.007
		ring.rings = 48
		ring.ring_segments = 8
		var track := mesh("Orbit", ring, brass, orbits, Vector3(0, i * 0.035, 0), false)
		track.rotation_degrees.z = (i - 1) * 14
		var angle := i * 2.1
		mesh("Planet", sphere(0.038 + i * 0.005), material([Color("5c9695"), Color("c17f60"), Color("8d82ab")][i], 0.2), orbits, Vector3(cos(angle) * radius, i * 0.035, sin(angle) * radius), false)
	plaque(instrument, Vector3(0, 0.10, 0.4), "TURN / REST")
	interact(instrument, 3, Vector3(0, 0.4, 0))

func decorate(builder: SceneTree) -> void:
	b = builder
	root = b.manor
	brass = material(Color("ad8850"), 0.65)
	flame = ShaderMaterial.new()
	flame.shader = load(BASE + "candle_flame.gdshader")
	for item: Node3D in root.find_children("CandleStick_Triple_*", "Node3D", true, false):
		candle(item)
	for frame: Node3D in root.find_children("Window_Wide_Round1_*", "Node3D", true, false):
		window(frame)
	orrery(root.get_node("WinterGallery"))
	# Keep the bottles as a little arrangement beside the moving instrument.
	for bottles: Node3D in root.find_children("SmallBottles_1_*", "Node3D", true, false):
		bottles.position.x += 0.15
		bottles.position.z += 0.65
	var music: Node3D
	for chest: Node3D in root.get_node("GuestParlour").get_children():
		if str(chest.name).begins_with("Chest_Wood_") and chest.scale.x < 0.5:
			music = chest
	# A metre-scale parent keeps the winding key and plaque independent of the kit scale.
	var winding := node("MusicBoxControl", root.get_node("GuestParlour"), music.position)
	var key := node("WindingKey", winding, Vector3(0, 0.24, 0))
	b.box("KeyStem", Vector3.ZERO, Vector3(0.025, 0.12, 0.025), brass, key).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for x in [-0.05, 0.05]:
		mesh("KeyWing", sphere(0.045), brass, key, Vector3(x, 0.055, 0), false)
	plaque(winding, Vector3(0, 0.008, 0.22), "WIND / STOP")
	interact(winding, 2, Vector3(0, 0.18, 0))
	winding.audio_path = winding.get_path_to(root.get_node("Atmosphere/gramophone"))
	var router := Node.new()
	router.set_script(load(BASE + "manor_interactions.gd"))
	b.add(router, root, "FurnishingInteractions")
