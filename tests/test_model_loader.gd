extends TestCase
## ModelLoader: runtime GLB loading + normalization so any authored model fits its
## ModelDef — length along -Z equal to length_m, wheels at y=0, centered laterally.

const EPS := 0.05

func _steam_def(length: float = 9.35) -> ModelDef:
	var d := ModelDef.new()
	d.id = &"steam_engine_1800s"
	d.mesh_path = "res://Assets/Engines/SteamEngine1800s/SteamEngine1800s.glb"
	d.length_m = length
	return d

func test_loads_real_asset() -> void:
	var node := ModelLoader.load_model(_steam_def())
	assert_true(node != null, "model loads")
	if node != null:
		node.free()

func test_normalized_to_def_length_and_grounded() -> void:
	var node := ModelLoader.load_model(_steam_def())
	var aabb := ModelLoader.merged_aabb(node)
	assert_approx(aabb.size.z, 9.35, "length matches def", EPS)
	assert_approx(aabb.position.y, 0.0, "wheels on ground", EPS)
	assert_approx(aabb.position.x + aabb.size.x * 0.5, 0.0, "centered on x", EPS)
	assert_approx(aabb.position.z + aabb.size.z * 0.5, 0.0, "centered on z", EPS)
	node.free()

func test_def_length_rescales_model() -> void:
	var node := ModelLoader.load_model(_steam_def(4.675))
	var aabb := ModelLoader.merged_aabb(node)
	assert_approx(aabb.size.z, 4.675, "half-length def halves the model", EPS)
	node.free()

func test_missing_file_returns_null() -> void:
	var d := ModelDef.new()
	d.mesh_path = "res://Assets/DoesNotExist.glb"
	assert_true(ModelLoader.load_model(d) == null, "null on missing file")
	var empty := ModelDef.new()
	assert_true(ModelLoader.load_model(empty) == null, "null on empty path")

func test_cache_returns_independent_instances() -> void:
	var a := ModelLoader.load_model(_steam_def())
	var b := ModelLoader.load_model(_steam_def())
	assert_true(a != null and b != null and a != b, "two distinct instances")
	a.free()
	b.free()
