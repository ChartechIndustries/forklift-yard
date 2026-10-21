class_name MP5
## Cosmetic low-poly MP5 prop. Never fires. MP5.attach(model) tucks one in the
## model's back pocket (on the Hips bone if there is one) so it follows animation,
## ragdoll tumbles and respawns.

const POCKET := Vector3(0.13, -0.1, -0.14)   # from the Hips bone, model faces +Z so -Z is the back


static func attach(model: Node3D) -> Node3D:
	var gun := build()
	var skel: Skeleton3D = null
	for s in model.find_children("*", "Skeleton3D", true, false):
		skel = s
		break
	var bone := -1
	if skel:
		for i in skel.get_bone_count():
			var n := skel.get_bone_name(i).to_lower()
			if "hips" in n or "pelvis" in n:
				bone = i
				break
	if skel and bone >= 0:
		var ba := BoneAttachment3D.new()
		ba.name = "MP5Attachment"
		skel.add_child(ba)
		ba.bone_name = skel.get_bone_name(bone)
		gun.position = POCKET
		ba.add_child(gun)
	else:
		gun.position = Vector3(0.13, 0.83, -0.14)
		model.add_child(gun)
	return gun


static func _mat(c: Color, rough := 0.45, metal := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material, rot_x := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees.x = rot_x
	parent.add_child(mi)


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "MP5"
	root.add_to_group("mp5")
	# the gun is built along +Z (barrel forward); the pivot stands it up so the barrel sticks out of the pocket
	var g := Node3D.new()
	g.rotation_degrees.x = -105.0
	g.rotation_degrees.y = 8.0
	root.add_child(g)
	var steel := _mat(Color(0.13, 0.14, 0.16))
	var dark := _mat(Color(0.07, 0.07, 0.08), 0.6, 0.4)
	_box(g, Vector3(0, 0, 0.08), Vector3(0.05, 0.07, 0.32), steel)                    # receiver
	_box(g, Vector3(0, 0, 0.26), Vector3(0.058, 0.058, 0.14), dark)                   # handguard
	_box(g, Vector3(0, 0.045, 0.1), Vector3(0.012, 0.025, 0.04), dark)                # sight
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.013
	cm.bottom_radius = 0.013
	cm.height = 0.14
	cm.material = steel
	barrel.mesh = cm
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0, 0, 0.4)
	g.add_child(barrel)
	_box(g, Vector3(0, -0.01, -0.2), Vector3(0.04, 0.065, 0.22), dark)                # stock
	_box(g, Vector3(0, -0.075, -0.03), Vector3(0.034, 0.1, 0.045), dark, 15.0)         # grip
	for i in 3:                                                                       # curved mag
		_box(g, Vector3(0, -0.1 - i * 0.075, 0.1 + i * 0.012 + i * i * 0.012), Vector3(0.03, 0.085, 0.04), dark, -8.0 * i)
	return root
