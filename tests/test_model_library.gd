extends TestCase
## ModelLibrary: the id -> ModelDef registry combining built-in defaults with
## scanned asset descriptors.

func test_builtins_present() -> void:
	var lib := ModelLibrary.new()
	lib.add_builtins()
	assert_true(lib.get_def(&"box_engine") != null, "box_engine builtin")
	assert_true(lib.get_def(&"box_car") != null, "box_car builtin")
	assert_eq(lib.get_def(&"box_engine").category, "engine", "builtin category")

func test_register_descriptor_builds_def() -> void:
	var lib := ModelLibrary.new()
	lib.register_descriptor({
		"id": "loco_a", "display_name": "Loco A", "category": "engine",
		"length_m": 12.5, "mass_kg": 35000.0, "path": "res://x/LocoA.glb"})
	var d := lib.get_def(&"loco_a")
	assert_true(d != null, "registered")
	assert_eq(d.display_name, "Loco A", "name")
	assert_approx(d.length_m, 12.5, "length")
	assert_eq(d.mesh_path, "res://x/LocoA.glb", "mesh path")

func test_duplicate_id_last_wins() -> void:
	var lib := ModelLibrary.new()
	lib.register_descriptor({"id": "x", "length_m": 5.0, "path": "a.glb"})
	lib.register_descriptor({"id": "x", "length_m": 7.0, "path": "b.glb"})
	assert_eq(lib.defs().size(), 1, "one def")
	assert_approx(lib.get_def(&"x").length_m, 7.0, "second registration wins")

func test_build_default_scans_project_assets() -> void:
	var lib := ModelLibrary.build_default()
	var steam := lib.get_def(&"steam_engine_1800s")
	assert_true(steam != null, "finds SteamEngine1800s.glb via sidecar")
	assert_approx(steam.length_m, 9.35, "sidecar length", 0.01)
	assert_eq(steam.category, "engine", "sidecar category")
	# The Tracks subfolder must NOT leak into the rolling-stock library.
	for d in lib.defs():
		assert_true(not d.mesh_path.contains("/Tracks/"), "no track pieces in library")

func test_default_engine_prefers_real_models() -> void:
	var lib := ModelLibrary.build_default()
	var eng := lib.default_engine()
	assert_true(eng != null, "an engine exists")
	assert_eq(String(eng.id), "steam_engine_1800s", "scanned model beats box builtin")

func test_default_engine_falls_back_to_builtin() -> void:
	var lib := ModelLibrary.new()
	lib.add_builtins()
	assert_eq(String(lib.default_engine().id), "box_engine", "builtin fallback")
