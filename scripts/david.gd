extends CharacterBody3D
## David: wanders the yard. Hit by a forklift, he goes ragdoll (a rigid capsule
## carries his model), tumbles, then respawns at home.

const SPEED := 1.4
const RAGDOLL_TIME := 4.0
const BOUNDS := Rect2(-13, -6, 19, 16.5)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var model: Node3D
var anim: AnimationPlayer
var anims := {}
var current := ""
var home := Vector3.ZERO
var target := Vector3.ZERO
var wait := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var ragdoll: RigidBody3D = null
var col: CollisionShape3D


func _ready() -> void:
	add_to_group("david")
	home = global_position
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.8
	col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	model = load("res://models/contestant.glb").instantiate()
	add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		anim = aps[0]
		for n in anim.get_animation_list():
			for key in ["Idle", "Walk", "Run"]:
				if key.to_lower() in n.to_lower():
					anims[key] = n
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_play("Idle")
	_pick_target()


func _pick_target() -> void:
	target = Vector3(randf_range(BOUNDS.position.x, BOUNDS.end.x), 0, randf_range(BOUNDS.position.y, BOUNDS.end.y))
	wait = randf_range(0.5, 3.0)
	stuck_t = 0.0


func _physics_process(delta: float) -> void:
	if ragdoll != null:
		return
	var to := target - global_position
	to.y = 0
	var moving := false
	if wait > 0.0:
		wait -= delta
	elif to.length() < 0.4:
		_pick_target()
	else:
		moving = true
		var dir := to.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), clamp(8.0 * delta, 0.0, 1.0))
		stuck_t += delta
		if stuck_t > 1.0:
			if global_position.distance_to(last_pos) < 0.3:
				_pick_target()
			last_pos = global_position
			stuck_t = 0.0
	if not moving:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_play("Walk" if moving else "Idle")
	if anim:
		anim.speed_scale = 1.0


func _play(key: String) -> void:
	if anim == null or not anims.has(key) or current == key:
		return
	current = key
	anim.play(anims[key], 0.25)


func is_down() -> bool:
	return ragdoll != null


## Send David flying. `dir` is the horizontal push direction, `spd` the impact speed.
func knock(dir: Vector3, spd: float) -> void:
	if ragdoll != null:
		return
	col.set_deferred("disabled", true)
	collision_layer = 0
	collision_mask = 0
	var rb := RigidBody3D.new()
	rb.mass = 70.0
	rb.linear_damp = 0.4
	rb.angular_damp = 0.8
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.6
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.8
	cs.shape = shape
	rb.add_child(cs)
	rb.add_to_group("ragdolls")
	get_parent().add_child(rb)
	rb.global_position = global_position + Vector3(0, 0.9, 0)
	model.reparent(rb, true)
	ragdoll = rb
	rb.linear_velocity = dir * spd * 1.3 + Vector3(0, 3.0 + spd * 0.5, 0)
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
	if anim and anims.has("Run"):
		anim.play(anims["Run"], 0.05)   # flail
		anim.speed_scale = 2.5
	get_tree().create_timer(RAGDOLL_TIME).timeout.connect(_get_up)


func _get_up() -> void:
	if ragdoll == null or not is_instance_valid(self):
		return
	model.reparent(self, false)
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	ragdoll.queue_free()
	ragdoll = null
	global_position = home
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 1
	col.disabled = false
	current = ""
	_play("Idle")
	if anim:
		anim.speed_scale = 1.0
	_pick_target()
