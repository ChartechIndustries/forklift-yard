extends Node3D
## Warehouse yard: walk to the forklift (E), pick pallets up from INBOUND and
## deliver them to the bay on your job ticket. Bay C is up the ramp on the dock.
## Run with `-- --autotest <dir>` to play a scripted shift and save screenshots.

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 col_a : source_color = vec3(0.33, 0.33, 0.35);
uniform vec3 col_b : source_color = vec3(0.27, 0.27, 0.29);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = floor(wp.xz / 2.0);
	ALBEDO = mix(col_a, col_b, mod(c.x + c.y, 2.0));
	vec2 g = abs(fract(wp.xz / 2.0) - 0.5);
	ALBEDO *= 1.0 - 0.25 * step(0.49, max(g.x, g.y));
	ROUGHNESS = 0.9;
}
"""
const ENTER_RANGE := 2.6
const INBOUND_SLOTS := [Vector3(-10, 0, 6), Vector3(-8, 0, 6), Vector3(-6, 0, 6), Vector3(-10, 0, 8.5),
	Vector3(-8, 0, 8.5), Vector3(-6, 0, 8.5)]
const BAYS := {"A": Vector3(7, 0, 5), "B": Vector3(7, 0, 0.5), "C": Vector3(9, 1.2, -10.5)}
const CRATE_COLORS := [Color(0.55, 0.38, 0.2), Color(0.25, 0.45, 0.7), Color(0.7, 0.25, 0.2), Color(0.35, 0.55, 0.3)]

var player: CharacterBody3D
var forklift: CharacterBody3D
var job_bay := ""
var job_time := 0.0
var money := 0
var delivered := 0
var last_bay := ""

var hud_job: Label
var hud_help: Label
var hud_prompt: Label
var hud_msg: Label
var msg_time := 0.0


func _ready() -> void:
	_environment()
	_floor()
	_props()
	_bays()
	forklift = CharacterBody3D.new()
	forklift.set_script(load("res://scripts/forklift.gd"))
	forklift.position = Vector3(-2.5, 0.05, 2.0)
	forklift.rotation.y = deg_to_rad(20)
	add_child(forklift)
	forklift.pallet_dropped.connect(_on_pallet_dropped)
	for i in 4:
		_spawn_pallet()
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.position = Vector3(0, 0.1, 6)
	add_child(player)
	_hud()
	_new_job()
	var args := OS.get_cmdline_user_args()
	if args.has("--autotest"):
		_autotest(args[args.find("--autotest") + 1])


# ---------------- world ----------------

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_mat.sky_horizon_color = Color(0.7, 0.72, 0.75)
	sky_mat.ground_horizon_color = Color(0.5, 0.5, 0.5)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _floor() -> void:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	mat.shader = sh
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), mat)


func _props() -> void:
	var crate := _mat(Color(0.55, 0.38, 0.2), 0.8)
	var concrete := _mat(Color(0.55, 0.55, 0.57), 0.95)
	var steel := _mat(Color(0.2, 0.32, 0.55), 0.5, 0.4)
	var hazard := _mat(Color(0.95, 0.65, 0.05), 0.6)

	for p in [Vector3(-5, 0, -2), Vector3(-6.2, 0, -2), Vector3(-5.6, 1.1, -2)]:
		_box(p + Vector3(0, 0.55, 0), Vector3(1.1, 1.1, 1.1), crate)
	# pallet racks
	for x in [-10.0, -6.0, -2.0]:
		for z in [-9.0, -7.6]:
			_box(Vector3(x, 1.6, z), Vector3(0.12, 3.2, 0.12), steel)
			_box(Vector3(x + 3.0, 1.6, z), Vector3(0.12, 3.2, 0.12), steel)
		for y in [0.15, 1.3, 2.45]:
			_box(Vector3(x + 1.5, y, -8.3), Vector3(3.1, 0.08, 1.5), steel)
		_box(Vector3(x + 1.5, 1.85, -8.3), Vector3(1.0, 0.9, 1.0), crate)
	# ramp (13.5 deg) from floor level at z=-2.5 up to the dock top (y=1.2) at z=-7.5
	var ramp := _box(Vector3(9, 0.5, -5.02), Vector3(3.2, 0.2, 6), concrete)
	ramp.rotation_degrees.x = 13.5
	_box(Vector3(9, 0.6, -10.5), Vector3(7, 1.2, 6), concrete)
	_box(Vector3(9, 1.21, -7.7), Vector3(7, 0.02, 0.3), hazard)
	# stairs
	for i in 8:
		_box(Vector3(2.5, 0.1 + i * 0.2, -10.5 + i * 0.35), Vector3(2.0, 0.2 + i * 0.4, 0.35), concrete)
	# pillars and low walls
	for p in [Vector3(-12, 0, 11), Vector3(13, 0, 11), Vector3(-12, 0, -14), Vector3(13, 0, -14)]:
		_box(p + Vector3(0, 2.5, 0), Vector3(0.6, 5, 0.6), concrete)
	_box(Vector3(0, 0.5, 12), Vector3(30, 1, 0.3), concrete)
	_box(Vector3(-15, 0.5, -1), Vector3(0.3, 1, 26), concrete)
	# inbound area marking + sign
	_paint_rect(Vector3(-8, 0, 7.25), Vector2(7.2, 5.0), Color(0.2, 0.75, 0.35))
	_sign("INBOUND", Vector3(-8, 2.6, 10.2), Color(0.3, 0.9, 0.45))


func _bays() -> void:
	for id in BAYS:
		var p: Vector3 = BAYS[id]
		_paint_rect(p, Vector2(2.6, 2.6), Color(0.95, 0.7, 0.05))
		_sign("BAY " + id, p + Vector3(0, 2.4, 0), Color(1, 0.8, 0.2))


func _paint_rect(center: Vector3, size: Vector2, col: Color) -> void:
	var m := _mat(col, 0.7)
	m.emission_enabled = true
	m.emission = col * 0.15
	var w := 0.1
	for e in [[Vector3(0, 0, -size.y / 2), Vector3(size.x, 0.01, w)], [Vector3(0, 0, size.y / 2), Vector3(size.x, 0.01, w)],
			[Vector3(-size.x / 2, 0, 0), Vector3(w, 0.01, size.y)], [Vector3(size.x / 2, 0, 0), Vector3(w, 0.01, size.y)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		bm.material = m
		mi.mesh = bm
		mi.position = center + e[0] + Vector3(0, 0.006, 0)
		add_child(mi)


func _sign(text: String, pos: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 18
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(l)


func _spawn_pallet() -> void:
	var free_slot = null
	for s in INBOUND_SLOTS:
		var taken := false
		for p in get_tree().get_nodes_in_group("pallets"):
			if p.global_position.distance_to(s) < 0.9:
				taken = true
		if not taken:
			free_slot = s
			break
	if free_slot == null:
		return
	var pallet := StaticBody3D.new()
	pallet.add_to_group("pallets")
	var wood := _mat(Color(0.62, 0.48, 0.3), 0.85)
	# deck boards on top, three stringers underneath (forks slot between them)
	for i in 5:
		_part(pallet, Vector3(0, 0.125, -0.42 + i * 0.21), Vector3(1.0, 0.03, 0.15), wood)
	for x in [-0.45, 0.0, 0.45]:
		_part(pallet, Vector3(x, 0.055, 0), Vector3(0.1, 0.11, 1.0), wood)
	var c := _mat(CRATE_COLORS[randi() % CRATE_COLORS.size()], 0.75)
	_part(pallet, Vector3(0, 0.59, 0), Vector3(0.9, 0.9, 0.9), c)
	var band := _mat(Color(0.1, 0.1, 0.1), 0.6)
	_part(pallet, Vector3(0, 0.59, 0), Vector3(0.92, 0.06, 0.92), band)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 1.04, 1.0)
	cs.shape = bs
	cs.position.y = 0.52
	pallet.add_child(cs)
	pallet.position = free_slot
	add_child(pallet)


func _part(parent: Node3D, pos: Vector3, size: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	_part(body, Vector3.ZERO, size, mat)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	return body


# ---------------- jobs ----------------

func _new_job() -> void:
	var ids := BAYS.keys()
	ids.erase(last_bay)
	job_bay = ids[randi() % ids.size()]
	last_bay = job_bay
	job_time = 0.0


func _on_pallet_dropped(p: Node3D) -> void:
	var bay := ""
	for id in BAYS:
		var b: Vector3 = BAYS[id]
		if abs(p.global_position.x - b.x) < 1.3 and abs(p.global_position.z - b.z) < 1.3 \
				and abs(p.global_position.y - b.y) < 0.6:
			bay = id
	if bay == "":
		return
	if bay != job_bay:
		_flash("Wrong bay! This ticket is for BAY %s" % job_bay, Color(1, 0.4, 0.3))
		return
	var bonus: int = max(0, 60 - int(job_time))
	var pay := 50 + bonus
	money += pay
	delivered += 1
	_flash("Delivered to BAY %s  +$%d" % [bay, pay], Color(0.4, 1, 0.5))
	p.remove_from_group("pallets")
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(p, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tw.tween_callback(p.queue_free)
	_spawn_pallet()
	_new_job()


# ---------------- HUD + input ----------------

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_job = _label(layer, Vector2(24, 20), 26)
	hud_help = _label(layer, Vector2(0, 0), 18)
	hud_help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hud_help.offset_left = 24
	hud_help.offset_top = -110
	hud_prompt = _label(layer, Vector2(0, 0), 28)
	hud_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud_prompt.offset_top = -170
	hud_prompt.offset_left = -200
	hud_prompt.offset_right = 200
	hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg = _label(layer, Vector2(0, 0), 36)
	hud_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_msg.offset_top = 90
	hud_msg.offset_left = -400
	hud_msg.offset_right = 400
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	parent.add_child(l)
	return l


func _flash(text: String, col: Color) -> void:
	hud_msg.text = text
	hud_msg.add_theme_color_override("font_color", col)
	msg_time = 3.0


func _process(delta: float) -> void:
	job_time += delta
	msg_time -= delta
	hud_msg.visible = msg_time > 0.0
	hud_job.text = "JOB TICKET:  Move a pallet from INBOUND to  BAY %s\nTime %d:%02d     Pay $%d     Delivered %d" % [
		job_bay, int(job_time) / 60, int(job_time) % 60, money, delivered]
	if forklift.driving:
		var state := "carrying a pallet" if forklift.carried else "forks empty"
		hud_help.text = "W/S drive   A/D steer   Space brake   R/F forks up/down   E get out\nMouse look   Wheel zoom   Esc free mouse\nForks %.1f m - %s" % [forklift.lift, state]
		hud_prompt.text = ""
	else:
		hud_help.text = "WASD walk   Shift run   Space jump   E drive forklift\nMouse look   Wheel zoom   Esc free mouse"
		var near := player.global_position.distance_to(forklift.global_position) < ENTER_RANGE
		hud_prompt.text = "[E] Drive forklift" if near else ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_toggle_drive()
		elif event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _toggle_drive() -> void:
	if forklift.driving:
		if abs(forklift.speed) > 0.5:
			return
		forklift.exit()
		var out := forklift.to_global(Vector3(-1.3, 0.1, 0.3))
		player.set_active(true, out, forklift.rotation.y)
	elif player.global_position.distance_to(forklift.global_position) < ENTER_RANGE:
		player.set_active(false)
		forklift.enter()


# ---------------- autotest ----------------

func _shot(out_dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("auto_%s.png" % name))
	print("AUTOTEST ", name, " driving=", forklift.driving, " lift=", snapped(forklift.lift, 0.01),
		" carried=", forklift.carried != null, " money=", money, " delivered=", delivered, " job=", job_bay)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _autotest(out_dir: String) -> void:
	await _wait(0.8)
	await _shot(out_dir, "f0_start")
	# walk up to the forklift and get in
	player.global_position = forklift.to_global(Vector3(-1.4, 0.1, 0.0))
	await _wait(0.3)
	_toggle_drive()
	await _wait(0.6)
	await _shot(out_dir, "f1_seated")
	# side close-up of the driver and the front wheel
	forklift.cam_yaw = -PI / 2
	forklift.cam_pitch = -0.15
	forklift.zoom = 3.2
	forklift.speed = 0.0
	await _wait(0.8)
	await _shot(out_dir, "f1b_driver_side")
	forklift.cam_yaw = -2.4
	await _wait(0.6)
	await _shot(out_dir, "f1c_driver_front")
	forklift.cam_yaw = 0.0
	forklift.cam_pitch = -0.35
	forklift.zoom = 6.0
	# line up behind the first pallet and creep the forks in
	var pallet: Node3D = get_tree().get_nodes_in_group("pallets")[0]
	forklift.global_rotation = Vector3.ZERO
	forklift.global_position = pallet.global_position + Vector3(0, 0.05, 3.6)
	forklift.auto_throttle = 0.35
	for i in 200:
		await get_tree().physics_frame
		if forklift.to_local(pallet.global_position).z > -1.62:
			break
	forklift.auto_throttle = 0.0
	forklift.speed = 0.0
	await _wait(0.4)
	await _shot(out_dir, "f2_forks_in")
	forklift.auto_lift = 1.0
	await _wait(0.8)
	forklift.auto_lift = 0.0
	await _shot(out_dir, "f3_lifted")
	# back out and drive off
	forklift.auto_throttle = -1.0
	await _wait(1.2)
	forklift.auto_throttle = 1.0
	forklift.cam_yaw = 0.7
	await _wait(1.0)
	forklift.auto_throttle = 0.0
	await _shot(out_dir, "f4_driving")
	# set down at the ticket's bay
	var b: Vector3 = BAYS[job_bay]
	forklift.speed = 0.0
	forklift.global_rotation = Vector3.ZERO
	forklift.global_position = b + Vector3(0, 0.05, 1.6)
	await _wait(0.5)
	forklift.auto_lift = -1.0
	await _wait(2.0)
	forklift.auto_lift = null
	await _wait(0.3)
	await _shot(out_dir, "f5_delivered")
	forklift.auto_throttle = null
	_toggle_drive()
	await _wait(0.5)
	await _shot(out_dir, "f6_walking_again")
	get_tree().quit()
