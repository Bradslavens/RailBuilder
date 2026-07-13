extends SceneTree
## Dev tool: report what the asset pipeline sees. For each scanned model:
## descriptor, whether the GLB loads, and its normalized size. Also checks the
## Assets/Tracks GLBs against the TrackAssets conventions (Entry/Exit markers).
##   godot4 --headless --path . --script res://tools/asset_probe.gd

func _initialize() -> void:
	print("=== AssetScanner over res://Assets ===")
	var descs := AssetScanner.scan(["res://Assets"])
	if descs.is_empty():
		print("  (nothing found)")
	for d in descs:
		print("  %s  id=%s  category=%s  length=%.2f" % [d.path, d.id, d.category, d.length_m])

	print("\n=== ModelLibrary / ModelLoader ===")
	var lib := ModelLibrary.build_default()
	for def in lib.defs():
		if def.mesh_path == "":
			print("  %s (builtin box)" % def.id)
			continue
		var node := ModelLoader.load_model(def)
		if node == null:
			print("  %s: FAILED TO LOAD %s" % [def.id, def.mesh_path])
			continue
		var aabb := ModelLoader.merged_aabb(node)
		print("  %s: ok  normalized size x=%.2f y=%.2f z=%.2f (def length %.2f)" %
			[def.id, aabb.size.x, aabb.size.y, aabb.size.z, def.length_m])
		node.free()

	print("\n=== Assets/Tracks vs TrackAssets conventions ===")
	var dir := DirAccess.open("res://Assets/Tracks")
	for f in dir.get_files():
		if f.get_extension().to_lower() != "glb":
			continue
		var path := "res://Assets/Tracks".path_join(f)
		var exit := TrackAssets.model_exit_transform(path)
		if exit == Transform3D.IDENTITY:
			print("  %s: NO *_Exit marker (or failed to load)" % f)
		else:
			print("  %s: ok  exit at (%.2f, %.2f, %.2f)" % [f,
				exit.origin.x, exit.origin.y, exit.origin.z])
	quit(0)
