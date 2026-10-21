extends SceneTree
## Headless smoke test: godot --headless --path . --script res://tests/smoke.gd
## Spawns the main scene, runs 300 frames, then forces crashes into David, a pallet,
## a crate, a barrel and checks that MESS goes up and oil slides the forklift.

var failures := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	var lvl: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(lvl)
	for i in 300:
		await physics_frame
	var fk: CharacterBody3D = lvl.forklift
	check(lvl.davids.size() > 0, "davids spawned")
	check(lvl.oil_patches.size() >= 4, "oil patches exist")
	check(get_nodes_in_group("cones").size() > 5 and get_nodes_in_group("barrels").size() > 3, "cones and barrels exist")
	var m0: int = lvl.mess

	# David: real forklift collision
	var d = lvl.davids[0]
	fk.global_position = d.global_position + Vector3(0, 0.05, 4.0)
	fk.global_rotation = Vector3.ZERO
	d.wait = 100.0
	fk.speed = 0.0
	fk.auto_throttle = 1.0
	for i in 240:
		await physics_frame
		if d.is_down():
			break
	fk.auto_throttle = 0.0
	check(d.is_down(), "david knocked down by forklift")
	check(lvl.mess >= m0 + 250, "mess rose for david (%d)" % lvl.mess)
	for i in 60 * 5:
		await physics_frame
	check(not d.is_down(), "david respawned")

	# pallet break (direct crash call)
	var pallets := get_nodes_in_group("pallets")
	var pn := pallets.size()
	var db0: int = lvl.debris.size()
	lvl._on_crash(pallets[0], 4.0, Vector3.FORWARD, Vector3.ZERO)
	for i in 30:
		await physics_frame
	check(get_nodes_in_group("pallets").size() == pn - 1, "pallet broke")
	check(lvl.debris.size() > db0 + 10, "debris spawned (%d)" % lvl.debris.size())

	# crate stack topples from a push
	var crate: RigidBody3D = get_nodes_in_group("crates")[0]
	var y0 := crate.global_position
	lvl._on_crash(crate, 3.0, Vector3.RIGHT, crate.global_position)
	for i in 60:
		await physics_frame
	check(crate.global_position.distance_to(y0) > 0.3, "crate moved")

	# barrel leak
	var oil0: int = lvl.oil_patches.size()
	for b in get_nodes_in_group("barrels"):
		if b.get_meta("leaky", false):
			lvl._on_crash(b, 4.0, Vector3.LEFT, b.global_position)
			break
	check(lvl.oil_patches.size() == oil0 + 1, "barrel leaked oil")

	# oil slide: drive onto a patch, cut the engine, forklift must keep drifting
	var o: Vector3 = lvl.oil_patches[1]
	fk.global_position = Vector3(o.x, 0.05, o.y + 2.5)
	fk.global_rotation = Vector3.ZERO
	fk.drift = Vector3.ZERO
	fk.speed = 0.0
	fk.auto_throttle = 1.0
	for i in 90:
		await physics_frame
	fk.auto_throttle = 0.0
	fk.speed = 0.0
	for i in 5:
		await physics_frame
	check(fk.slip and fk.drift.length() > 0.5, "forklift sliding on oil (drift %.2f)" % fk.drift.length())

	# deliveries still work
	var money0: int = lvl.money
	var p: Node3D = get_nodes_in_group("pallets")[0]
	p.global_position = lvl.BAYS[lvl.job_bay] + Vector3(0, 0.05, 0)
	lvl._on_pallet_dropped(p)
	check(lvl.money > money0, "delivery pays")

	for i in 60:
		await physics_frame
	print("MESS final ", lvl.mess, " failures ", failures)
	quit(1 if failures > 0 else 0)
