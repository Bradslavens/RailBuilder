extends Node
## Dev tool: launch a view with a seeded demo layout, screenshot it, quit.
## Runs as a scene so autoloads (GameState) are live:
##   RB_SHOT=/tmp/out.png RB_VIEW=build2d godot4 --path . res://tools/ui_shot.tscn
## RB_VIEW: build2d (default) | ride3d.  RB_TICKS: sim seconds to advance (default 6).
## RB_CAR: model id to couple behind the engine (default: the first modeled car),
## e.g. RB_CAR=passengercar_oldwest to shoot a specific asset.
##
## Godot ships as a snap here, which has a private /tmp — a RB_SHOT path under
## /tmp is silently unwritable (save_png returns ERR_FILE_CANT_OPEN). Point it
## somewhere under $HOME.

func _ready() -> void:
	_seed_world()
	var view := "ride3d" if OS.get_environment("RB_VIEW") == "ride3d" else "build2d"
	var scene: Node = load("res://views/%s/%s.tscn" % [view, view]).instantiate()
	add_child(scene)
	# RB_ZOOM / RB_PAN ("x,y" metres) frame the 2D map, so a shot can pull back far
	# enough to fit a large scenery model that the default zoom crops away. The
	# map is the HSplit/Map child; the scene root is just the editor shell.
	var map: Node = scene.get_node_or_null("HSplit/Map")
	if map != null:
		if OS.get_environment("RB_ZOOM") != "":
			map.set("_zoom", float(OS.get_environment("RB_ZOOM")))
		var pan := OS.get_environment("RB_PAN").split(",")
		if pan.size() == 2:
			map.set("_cam_world", Vector2(float(pan[0]), float(pan[1])))
		map.queue_redraw()
	_capture.call_deferred()

func _seed_world() -> void:
	var w := GameState.world
	var defs := [
		{"t": "s", "len": 6.0}, {"t": "a", "deg": 90.0}, {"t": "a", "deg": 45.0},
		{"t": "a", "deg": 45.0}, {"t": "s", "len": 6.0}, {"t": "a", "deg": 30.0},
		{"t": "a", "deg": 30.0}, {"t": "a", "deg": 30.0}, {"t": "a", "deg": 90.0},
	]
	var pose := Transform2D(0.0, Vector2(-6.0, -6.0))
	for d in defs:
		var e: TrackEdge = StraightEdge.new(pose, d.len) if d.t == "s" else ArcEdge.new(pose, 6.0, deg_to_rad(d.deg))
		w.track.add_edge(e)
		pose = e.end_pose()
	# A detached spur (not touching the loop) so open endpoints show in 2D.
	w.track.add_edge(StraightEdge.new(Transform2D(0.3, Vector2(12.0, 2.0)), 6.0))

	# Signals on two loop joints -> two blocks; some painted terrain.
	w.toggle_signal_at(w.track.edges[0].end_pose().origin)
	w.toggle_signal_at(w.track.edges[5].end_pose().origin)
	for i in range(4):
		w.paint_terrain(Vector2i(-8 + i, -6), "mountain")
		w.paint_terrain(Vector2i(6, -3 + i), "water")
	w.paint_terrain(Vector2i(-7, -5), "forest")
	w.paint_terrain(Vector2i(-6, -5), "forest")

	# A player-built train: engine + two cars coupled on the loop. Prefer a
	# modeled car (e.g. the Old West boxcar) over the box primitive.
	var lib := ModelLibrary.build_default()
	var eng := lib.default_engine()
	var box := lib.get_def(&"box_car")
	for def in lib.by_category("car"):
		if def.mesh_path != "":
			box = def
			break
	# RB_CAR names a specific car to shoot instead of whichever modeled car scans first.
	var want := OS.get_environment("RB_CAR")
	if want != "":
		var picked := lib.get_def(StringName(want))
		if picked == null:
			push_warning("RB_CAR=%s not in the library; using %s" % [want, box.id])
		else:
			box = picked
	# RB_SCENERY places a scenery model beyond the loop, e.g.
	# RB_SCENERY=mountainrange_snow. It goes on +y, which is the far side of the
	# layout from the aerial camera, and is stood off by its own half-length so a
	# big one frames the track instead of burying it.
	var scenery_id := OS.get_environment("RB_SCENERY")
	if scenery_id != "":
		var sdef := lib.get_def(StringName(scenery_id))
		if sdef == null:
			push_warning("RB_SCENERY=%s not in the library" % scenery_id)
		else:
			w.place_scenery(sdef.id, Vector2(0.0, sdef.length_m * 0.5 + 40.0))

	var placed := TrainBuilder.place_vehicle(w, eng, Vector2(0.0, -6.0))
	if bool(placed.ok):
		var train: Consist = placed.consist
		for _i in range(2):
			TrainBuilder.place_vehicle(w, box, train.coupler_points().back)
		train.target_speed = 8.0
	var secs := 6.0
	if OS.get_environment("RB_TICKS") != "":
		secs = float(OS.get_environment("RB_TICKS"))
	for _i in range(int(secs * 60.0)):
		w.tick(1.0 / 60.0)

func _capture() -> void:
	for _i in range(12):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("RB_SHOT")
	if out == "":
		out = "/tmp/railbuilder_ui.png"
	img.save_png(out)
	print("shot saved: ", out)
	get_tree().quit()
