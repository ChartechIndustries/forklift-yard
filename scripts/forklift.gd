extends CharacterBody3D
## Drivable forklift. W/S throttle, A/D steer, Space brake, R/F forks up/down,
## mouse orbits the camera. Pallets are picked up by sliding the forks under one
## and raising; they are set down by lowering the forks all the way.

signal pallet_dropped(pallet: Node3D)

const MAX_SPEED := 4.5
const MAX_REVERSE := 2.5
const ACCEL := 3.0
const BRAKE := 9.0
const COAST := 1.5
const WHEELBASE := 1.4
const MAX_STEER := deg_to_rad(40.0)
const STEER_RATE := 2.5
const LIFT_SPEED := 0.6
const MAX_LIFT := 1.9
const MOUSE_SENS := 0.0025
# driver origin, measured from the Sit pose: butt 0.835 above origin -> seat top 1.225,
# soles 0.39 above origin -> floor plate 0.78; sits 8 cm forward of the backrest
const SEAT := Vector3(0, 0.39, 0.48)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var driving := false
var speed := 0.0
var steer := 0.0
var lift := 0.0
var spin := 0.0
var carried: Node3D = null
# autotest overrides (null = read the keyboard)
var auto_throttle = null
var auto_lift = null

var model: Node3D
var carriage: Node3D
var carriage_rest: Vector3
var wheels := {}
var driver: Node3D
var driver_anim: AnimationPlayer
var beacon: OmniLight3D
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.35
var zoom := 6.0
var t := 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(30)
	floor_snap_length = 0.3
	model = load("res://models/forklift.glb").instantiate()
	add_child(model)
	carriage = model.find_child("Carriage", true, false)
	carriage_rest = carriage.position
	for n in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		wheels[n] = model.find_child(n, true, false)

	_box_shape(Vector3(0, 0.65, 0.27), Vector3(1.2, 1.3, 2.5))     # chassis + mast; forks have no collider

	driver = load("res://models/contestant.glb").instantiate()
	driver.position = SEAT
	driver.rotation.y = PI
	driver.visible = false
	add_child(driver)
	var aps := driver.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		driver_anim = aps[0]
		for n in driver_anim.get_animation_list():
			if "sit" in n.to_lower():
				driver_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
				driver_anim.play(n)

	beacon = OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.55, 0.1)
	beacon.omni_range = 4.0
	beacon.position = Vector3(0.4, 2.3, 0.8)
	add_child(beacon)
	for x in [-0.5, 0.5]:
		var head := SpotLight3D.new()
		head.position = Vector3(x, 1.92, -0.4)
		head.rotation_degrees.x = -12
		head.spot_range = 12
		head.spot_angle = 30
		head.light_energy = 2.0
		add_child(head)

	pivot = Node3D.new()
	pivot.position.y = 2.0
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = zoom
	spring.margin = 0.2
	spring.add_excluded_object(get_rid())
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65
	spring.add_child(camera)


func _box_shape(offset: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	add_child(cs)


func enter() -> void:
	driving = true
	driver.visible = true
	cam_yaw = 0.0
	camera.make_current()


func exit() -> void:
	driving = false
	driver.visible = false
	speed = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not driving:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * MOUSE_SENS
		cam_pitch = clamp(cam_pitch - event.relative.y * MOUSE_SENS, -1.2, 0.4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = max(3.0, zoom - 0.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = min(12.0, zoom + 0.4)


func _key(k: Key) -> float:
	return 1.0 if driving and Input.is_physical_key_pressed(k) else 0.0


func _physics_process(delta: float) -> void:
	t += delta
	# --- input ---
	var throttle: float = auto_throttle if auto_throttle != null else _key(KEY_W) - _key(KEY_S)
	var steer_in := _key(KEY_A) - _key(KEY_D)
	var lift_in: float = auto_lift if auto_lift != null else _key(KEY_R) - _key(KEY_F)
	var braking := _key(KEY_SPACE) > 0.0

	# --- speed: throttle against the direction of travel brakes first ---
	if braking:
		speed = move_toward(speed, 0.0, BRAKE * delta)
	elif throttle != 0.0:
		var rate := BRAKE if sign(throttle) != sign(speed) and abs(speed) > 0.1 else ACCEL
		speed = clamp(speed + throttle * rate * delta, -MAX_REVERSE, MAX_SPEED)
	else:
		speed = move_toward(speed, 0.0, COAST * delta)

	var steer_target := steer_in * MAX_STEER
	steer = move_toward(steer, steer_target, STEER_RATE * delta)
	rotation.y += speed / WHEELBASE * tan(steer) * delta

	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if is_on_wall():
		speed *= 0.5

	# --- forks ---
	var prev_lift := lift
	lift = clamp(lift + lift_in * LIFT_SPEED * delta, 0.0, MAX_LIFT)
	carriage.position = carriage_rest + Vector3(0, lift, 0)
	if carried == null and prev_lift <= 0.05 and lift > 0.05:
		_try_pickup()
	elif carried != null and lift <= 0.0 and lift_in < 0.0:
		_drop()

	# --- visuals: wheels roll, rear wheels steer, beacon flashes while moving ---
	spin -= speed * delta / 0.3
	for n in wheels:
		var w: Node3D = wheels[n]
		var r := 0.33 if n.begins_with("Wheel_F") else 0.25
		w.rotation = Vector3(spin * 0.3 / r, -steer if n.begins_with("Wheel_R") else 0.0, 0)
	beacon.light_energy = (1.5 + 1.5 * sin(t * 12.0)) if (driving and abs(speed) > 0.1) else 0.0

	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	spring.spring_length = lerp(spring.spring_length, zoom, 8.0 * delta)


func _try_pickup() -> void:
	for p in get_tree().get_nodes_in_group("pallets"):
		var local := to_local(p.global_position)
		var dyaw := fposmod(p.global_rotation.y - global_rotation.y + PI / 4, PI / 2) - PI / 4
		if abs(local.x) < 0.25 and local.z < -1.3 and local.z > -2.0 and abs(dyaw) < deg_to_rad(20) \
				and abs(local.y) < 0.3:
			carried = p
			p.reparent(carriage, true)
			p.collision_layer = 0
			p.collision_mask = 0
			# square it up on the forks
			var tw := create_tween()
			tw.tween_property(p, "rotation", Vector3(0, p.rotation.y - dyaw, 0), 0.25)
			tw.parallel().tween_property(p, "position:x", 0.0, 0.25)
			return


func _drop() -> void:
	var p := carried
	carried = null
	p.reparent(get_parent(), true)
	p.global_position.y = global_position.y
	p.rotation.x = 0
	p.rotation.z = 0
	p.collision_layer = 1
	p.collision_mask = 1
	pallet_dropped.emit(p)
