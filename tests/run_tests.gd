extends SceneTree
## Headless test runner. Invoke with:
##   godot4 --headless --path <project> --script res://tests/run_tests.gd
## Exits 0 if all assertions pass, 1 otherwise.

const TEST_SCRIPTS := [
	"res://tests/test_straight_edge.gd",
	"res://tests/test_arc_edge.gd",
	"res://tests/test_track_graph.gd",
	"res://tests/test_serializer.gd",
	"res://tests/test_track_path.gd",
	"res://tests/test_path_builder.gd",
	"res://tests/test_consist.gd",
	"res://tests/test_train_builder.gd",
	"res://tests/test_signals.gd",
	"res://tests/test_collisions.gd",
	"res://tests/test_integration.gd",
	"res://tests/test_geo3d.gd",
	"res://tests/test_track_mesh.gd",
	"res://tests/test_piece_catalog.gd",
	"res://tests/test_track_assets.gd",
	"res://tests/test_asset_scanner.gd",
	"res://tests/test_model_library.gd",
	"res://tests/test_model_loader.gd",
]

func _initialize() -> void:
	var total_methods := 0
	var all_failures: Array[String] = []

	for path in TEST_SCRIPTS:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			all_failures.append("%s: could not load/parse script" % path)
			continue
		var inst: TestCase = script.new()
		if inst == null:
			all_failures.append("%s: failed to instantiate" % path)
			continue
		for m in inst.get_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			inst.current_test = "%s.%s" % [path.get_file(), mname]
			total_methods += 1
			inst.call(mname)
		for f in inst.failures():
			all_failures.append(f)

	print("\n==== RailBuilder tests ====")
	for f in all_failures:
		print("FAIL  ", f)
	print("Ran %d test methods, %d assertion failures" % [total_methods, all_failures.size()])
	if all_failures.is_empty():
		print("ALL GREEN")
		quit(0)
	else:
		print("RED")
		quit(1)
