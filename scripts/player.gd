extends CharacterBody3D
## Third-person contestant: WASD to move, Shift to run, Space to jump,
## mouse to orbit the camera, wheel to zoom, Esc to free the mouse.

const WALK_SPEED := 1.5
const RUN_SPEED := 4.2
const JUMP_VELOCITY := 4.2
const ACCEL := 10.0
const TURN_SPEED := 10.0
const MOUSE_SENS := 0.0025
# speeds the cycles were authored for, so feet don't skate
const WALK_ANIM_SPEED := 1.4
const RUN_ANIM_SPEED := 4.2

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var cam_yaw := 0.0
var cam_pitch := -0.3
var zoom := 3.2
var auto_input := Vector2.ZERO   # set by the autotest instead of the keyboard
var auto_run := false
var active := true

var model: Node3D
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var anim: AnimationPlayer
var anim_names := {}
var current := ""


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	model = load("res://models/contestant.glb").instantiate()
	add_child(model)

	pivot = Node3D.new()
	pivot.position.y = 1.55
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = zoom
	spring.margin = 0.2
	spring.add_excluded_object(get_rid())
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 65
	spring.add_child(camera)
	camera.make_current()

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		anim = players[0]
		for n in anim.get_animation_list():
			for key in ["Idle", "Walk", "Run"]:
				if key.to_lower() in n.to_lower():
					anim_names[key] = n
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	else:
		push_warning("contestant.glb has no AnimationPlayer")
	_play("Idle")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam_yaw -= event.relative.x * MOUSE_SENS
		cam_pitch = clamp(cam_pitch - event.relative.y * MOUSE_SENS, -1.2, 0.6)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = max(1.2, zoom - 0.3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = min(8.0, zoom + 0.3)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Hide and freeze the walker (while driving), or bring them back at `where`.
func set_active(on: bool, where := Vector3.ZERO, facing := 0.0) -> void:
	active = on
	visible = on
	$CollisionShape3D.disabled = not on
	velocity = Vector3.ZERO
	if on:
		global_position = where
		cam_yaw = facing
		model.rotation.y = facing + PI
		camera.make_current()


func _physics_process(delta: float) -> void:
	if not active:
		return
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	spring.spring_length = lerp(spring.spring_length, zoom, 10.0 * delta)

	var input := auto_input
	if input == Vector2.ZERO:
		input = Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	input = input.limit_length(1.0)
	var running := auto_run or Input.is_physical_key_pressed(KEY_SHIFT)
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, cam_yaw)
	var target_speed := (RUN_SPEED if running else WALK_SPEED) * dir.length()

	var horiz := Vector3(velocity.x, 0, velocity.z)
	horiz = horiz.lerp(dir.normalized() * target_speed, clamp(ACCEL * delta, 0.0, 1.0))
	velocity.x = horiz.x
	velocity.z = horiz.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY
	move_and_slide()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb and rb.freeze == false:
			rb.apply_impulse(-c.get_normal() * 2.0 * minf(rb.mass, 20.0) * 0.25, c.get_position() - rb.global_position)

	# the model faces +Z; turn it toward the travel direction
	if dir.length() > 0.1:
		var target_yaw := atan2(dir.x, dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clamp(TURN_SPEED * delta, 0.0, 1.0))

	var speed := Vector3(velocity.x, 0, velocity.z).length()
	if speed < 0.15:
		_play("Idle")
		_set_speed(1.0)
	elif speed < (WALK_SPEED + RUN_SPEED) * 0.5:
		_play("Walk")
		_set_speed(speed / WALK_ANIM_SPEED)
	else:
		_play("Run")
		_set_speed(speed / RUN_ANIM_SPEED)


func _play(key: String) -> void:
	if anim == null or not anim_names.has(key) or current == key:
		return
	current = key
	anim.play(anim_names[key], 0.25)


func _set_speed(s: float) -> void:
	if anim:
		anim.speed_scale = clamp(s, 0.4, 1.6)
