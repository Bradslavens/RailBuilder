class_name ModelLoader
extends RefCounted
## Runtime GLB loading for rolling stock, with normalization so ANY reasonably
## authored model fits its ModelDef: front along -Z (per def.forward_axis), scaled
## so the length equals def.length_m, centered laterally and on the wheelbase, and
## grounded so the wheels sit at y = 0 (+ def.y_offset). Loaded prototypes are
## cached; callers get independent duplicates.

static var _proto_cache: Dictionary = {}   # mesh_path -> Node3D or null

## Load, normalize, and return a fresh instance for this def (null on failure).
static func load_model(def: ModelDef) -> Node3D:
	if def == null or def.mesh_path == "":
		return null
	if not _proto_cache.has(def.mesh_path):
		_proto_cache[def.mesh_path] = _load_gltf(def.mesh_path)
	var proto: Node3D = _proto_cache[def.mesh_path]
	if proto == null:
		return null
	var inst: Node3D = proto.duplicate()
	var holder := Node3D.new()
	holder.name = String(def.id) if def.id != &"" else "Model"
	holder.add_child(inst)
	inst.transform = _normalization(inst, def)
	return holder

static func _load_gltf(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)

## The transform that maps the raw model into def-conformant space.
static func _normalization(model: Node3D, def: ModelDef) -> Transform3D:
	var rot := Basis.IDENTITY
	match def.forward_axis:
		"x":  rot = Basis(Vector3.UP, PI / 2.0)     # +X front -> -Z
		"-x": rot = Basis(Vector3.UP, -PI / 2.0)
		"z":  rot = Basis(Vector3.UP, PI)
	var raw := merged_aabb(model)
	if raw.size.length() < 0.0001:
		return Transform3D.IDENTITY
	var rotated := Transform3D(rot, Vector3.ZERO) * raw
	var s := 1.0
	if rotated.size.z > 0.0001 and def.length_m > 0.0:
		s = def.length_m / rotated.size.z
	var basis := rot.scaled(Vector3.ONE * s)
	var scaled := Transform3D(basis, Vector3.ZERO) * raw
	var offset := Vector3(
		-(scaled.position.x + scaled.size.x * 0.5),
		-scaled.position.y + def.y_offset,
		-(scaled.position.z + scaled.size.z * 0.5))
	return Transform3D(basis, offset)

## Merged AABB of all MeshInstance3D descendants in NODE-local space (works on
## nodes not in a tree, accumulating local transforms manually).
static func merged_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform if n != node else Transform3D.IDENTITY
			if n is MeshInstance3D:
				var a: AABB = xf * (n as MeshInstance3D).get_aabb()
				out = a if first else out.merge(a)
				first = false
		for c in n.get_children():
			stack.append([c, xf])
	return out
