extends TestCase
## Serializer: World <-> dict <-> file round-trips preserve track geometry.

func test_dict_roundtrip_preserves_edges() -> void:
	var w := World.new()
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	w.track.add_edge(ArcEdge.new(Transform2D(0.0, Vector2(4, 0)), 6.0, PI / 6.0))

	var w2 := Serializer.world_from_dict(w.to_dict())
	assert_eq(w2.track.edges.size(), 2, "edge count preserved")

	var e0 = w2.track.edges[0]
	assert_true(e0 is StraightEdge, "first edge is straight")
	assert_approx(e0.length(), 4.0, "straight length preserved")

	var e1 = w2.track.edges[1]
	assert_true(e1 is ArcEdge, "second edge is arc")
	var d := e1.end_pose().origin.distance_to(w.track.edges[1].end_pose().origin)
	assert_approx(d, 0.0, "arc geometry preserved")

func test_next_id_continues_after_load() -> void:
	var w := World.new()
	w.track.add_edge(StraightEdge.new(Transform2D.IDENTITY, 4.0))
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(4, 0)), 4.0))
	var w2 := Serializer.world_from_dict(w.to_dict())
	var added := w2.track.add_edge(StraightEdge.new(Transform2D.IDENTITY, 4.0))
	assert_eq(added.id, 3, "id counter resumes after load")

func test_v2_roundtrip_signals_terrain_consists() -> void:
	var w := World.new()
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 10.0))
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(10, 0)), 10.0))
	w.toggle_signal_at(Vector2(10, 0))
	w.paint_terrain(Vector2i(3, -2), "water")
	w.paint_terrain(Vector2i(0, 0), "mountain")
	var def := ModelDef.new()
	def.id = &"steam_engine_1800s"
	def.category = "engine"
	def.length_m = 9.35
	def.mass_kg = 30000.0
	TrainBuilder.place_vehicle(w, def, Vector2(12, 0.5))
	var c: Consist = w.consists[0]
	c.cars[0].health = 62.0
	c.target_speed = 5.0

	var w2 := Serializer.world_from_dict(w.to_dict())
	assert_eq(w2.signals.size(), 1, "signal restored")
	assert_eq(String(w2.terrain.get(Vector2i(3, -2), "")), "water", "terrain cell restored")
	assert_eq(w2.terrain.size(), 2, "all terrain cells restored")
	assert_eq(w2.consists.size(), 1, "consist restored")
	var c2: Consist = w2.consists[0]
	assert_eq(c2.cars.size(), 1, "cars restored")
	assert_eq(String(c2.cars[0].model_id), "steam_engine_1800s", "model id restored")
	assert_approx(c2.cars[0].health, 62.0, "health restored")
	assert_approx(c2.target_speed, 5.0, "target speed restored")
	assert_vec_approx(
		c2.path.pose_at_distance(c2.distance).origin,
		c.path.pose_at_distance(c.distance).origin,
		"train stands in the same world spot after load")
	# Blocks work after load: the restored signal still splits the line.
	var bm := w2.blocks()
	assert_true(bm.block_of[1] != bm.block_of[2], "restored signal splits blocks")

func test_file_roundtrip() -> void:
	var w := World.new()
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	var path := "user://test_layout.json"
	assert_eq(Serializer.save_to_file(w, path), OK, "save ok")
	var w2 := Serializer.load_from_file(path)
	assert_true(w2 != null, "loaded non-null")
	assert_eq(w2.track.edges.size(), 1, "edge preserved through file")
