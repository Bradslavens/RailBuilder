extends TestCase
## TrainBuilder: placing vehicles on track, coupling to consist ends, and
## removing/splitting. Also the TrackPath interval helpers it relies on.

func _straight_world() -> World:
	# Three 10 m straights in a row along +x: total 30 m, ids 1/2/3.
	var w := World.new()
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 10.0))
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(10, 0)), 10.0))
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(20, 0)), 10.0))
	return w

func _def(id: String, category: String, length: float) -> ModelDef:
	var d := ModelDef.new()
	d.id = StringName(id)
	d.category = category
	d.length_m = length
	d.mass_kg = 30000.0
	return d

# ---------- TrackPath helpers ----------

func test_distance_of_maps_edge_point_to_path() -> void:
	var w := _straight_world()
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	assert_approx(path.distance_of(1, 4.0), 4.0, "on first edge")
	assert_approx(path.distance_of(2, 4.0), 14.0, "on second edge")
	assert_approx(path.distance_of(99, 0.0), -1.0, "unknown edge")

func test_distance_of_reversed_start() -> void:
	var w := _straight_world()
	var path := PathBuilder.build_from(w.track, w.track.edges[2], true)
	# Walking backwards from edge 3: path d=0 is at world x=30, d=4 at x=26 (edge 3 s=6).
	assert_approx(path.distance_of(3, 6.0), 4.0, "reversed segment mapping")

func test_map_interval_spans_edges() -> void:
	var w := _straight_world()
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	var iv := path.map_interval(8.0, 13.0)
	assert_eq(iv.size(), 2, "interval crosses one boundary")
	assert_eq(int(iv[0].edge_id), 1, "first edge id")
	assert_approx(float(iv[0].a), 8.0, "first span start")
	assert_approx(float(iv[0].b), 10.0, "first span end")
	assert_approx(float(iv[1].a), 0.0, "second span start")
	assert_approx(float(iv[1].b), 3.0, "second span end")

func test_map_interval_wraps_on_loop() -> void:
	var w := World.new()
	# A 4-edge square-ish loop of 90° arcs, radius 6 (quarter circle length ~9.42).
	var pose := Transform2D.IDENTITY
	for _i in range(4):
		var e := ArcEdge.new(pose, 6.0, PI / 2.0)
		w.track.add_edge(e)
		pose = e.end_pose()
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	assert_true(path.is_loop, "loop detected")
	var tl := path.total_length()
	var iv := path.map_interval(tl - 2.0, tl + 3.0)
	var covered := 0.0
	for s in iv:
		covered += float(s.b) - float(s.a)
	assert_approx(covered, 5.0, "wrapped interval keeps full length", 0.01)

# ---------- placement ----------

func test_place_creates_consist_on_track() -> void:
	var w := _straight_world()
	var res := TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 1.0))
	assert_true(bool(res.ok), "placed")
	assert_eq(w.consists.size(), 1, "one consist")
	var c: Consist = res.consist
	assert_eq(c.cars.size(), 1, "one car")
	assert_eq(c.cars[0].kind, "engine", "kind from category")
	assert_approx(c.distance, 19.0, "front = click + half length", 0.3)
	assert_true(c.has_engine(), "has engine")

func test_place_too_far_fails() -> void:
	var w := _straight_world()
	var res := TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 8.0))
	assert_true(not bool(res.ok), "too far from track")
	assert_eq(w.consists.size(), 0, "nothing placed")

func test_place_near_back_couples() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(20, 0.5))
	var back: Vector2 = w.consists[0].coupler_points().back
	var res := TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), back + Vector2(-1.0, 0.3))
	assert_true(bool(res.ok) and bool(res.coupled), "coupled at back")
	assert_eq(w.consists.size(), 1, "still one consist")
	assert_eq(w.consists[0].cars.size(), 2, "two cars")
	assert_eq(w.consists[0].cars[1].kind, "car", "appended behind")

func test_place_near_front_couples_and_extends_forward() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(12, 0.5))
	var c: Consist = w.consists[0]
	var d0 := c.distance
	var front: Vector2 = c.coupler_points().front
	var res := TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), front + Vector2(1.0, 0.3))
	assert_true(bool(res.ok) and bool(res.coupled), "coupled at front")
	assert_eq(c.cars.size(), 2, "two cars")
	assert_eq(c.cars[0].kind, "car", "prepended in front")
	assert_approx(c.distance, d0 + 6.0 + Consist.COUPLER_GAP, "front advanced")

func test_place_on_top_of_train_rejected() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 0.5))
	var res := TrainBuilder.place_vehicle(w, _def("e2", "engine", 8.0), Vector2(14.5, 0.5))
	assert_true(not bool(res.ok) or bool(res.coupled), "overlap rejected unless coupling")
	# Clicking mid-train is within couple range of neither end here (train spans 11..19).
	assert_eq(w.consists.size(), 1, "no overlapping consist added")

func test_flipped_placement_reverses_heading() -> void:
	var w := _straight_world()
	var res := TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 0.5), true)
	assert_true(bool(res.ok), "placed flipped")
	var c: Consist = res.consist
	var rot := c.path.pose_at_distance(c.distance).get_rotation()
	assert_approx(absf(angle_difference(rot, PI)), 0.0, "heading points -x", 0.01)

# ---------- removal ----------

func _three_car_train(w: World) -> Consist:
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(24, 0.5))
	var c: Consist = w.consists[0]
	TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), c.coupler_points().back)
	TrainBuilder.place_vehicle(w, _def("c2", "car", 6.0), c.coupler_points().back)
	return c

func test_remove_last_car() -> void:
	var w := _straight_world()
	var c := _three_car_train(w)
	var pls := c.car_placements()
	var mid: Vector2 = (pls[2].front + pls[2].back) * 0.5
	var res := TrainBuilder.remove_car_at(w, mid)
	assert_true(bool(res.ok), "removed")
	assert_eq(c.cars.size(), 2, "two cars left")
	assert_eq(w.consists.size(), 1, "no split")

func test_remove_middle_car_splits() -> void:
	var w := _straight_world()
	var c := _three_car_train(w)
	var before := c.car_placements()
	var mid: Vector2 = (before[1].front + before[1].back) * 0.5
	var rear_mid: Vector2 = (before[2].front + before[2].back) * 0.5
	var res := TrainBuilder.remove_car_at(w, mid)
	assert_true(bool(res.ok) and bool(res.split), "split")
	assert_eq(w.consists.size(), 2, "two consists")
	assert_eq(w.consists[0].cars.size(), 1, "front keeps engine")
	assert_eq(w.consists[1].cars.size(), 1, "rear keeps last car")
	var after: Vector2 = (w.consists[1].car_placements()[0].front + w.consists[1].car_placements()[0].back) * 0.5
	assert_vec_approx(after, rear_mid, "rear car stayed in place", 0.05)

func test_remove_only_car_removes_consist() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 0.5))
	var pls: Array = w.consists[0].car_placements()
	var mid: Vector2 = (pls[0].front + pls[0].back) * 0.5
	assert_true(bool(TrainBuilder.remove_car_at(w, mid).ok), "removed")
	assert_eq(w.consists.size(), 0, "consist gone")

func test_click_where_car_body_sits_couples() -> void:
	# The natural gesture: click half a car length behind the train's rear
	# coupler (where the new car's body would sit) — must couple, not spawn a
	# second train.
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(20, 0.5))
	var back: Vector2 = w.consists[0].coupler_points().back
	var res := TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), back + Vector2(-3.5, 0.4))
	assert_true(bool(res.ok) and bool(res.coupled), "coupled from body-position click")
	assert_eq(w.consists.size(), 1, "no second consist")
	assert_eq(w.consists[0].cars.size(), 2, "car appended")

func test_far_click_starts_separate_consist() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(22, 0.5))
	var res := TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), Vector2(5, 0.5))
	assert_true(bool(res.ok) and not bool(res.coupled), "far drop stays separate")
	assert_eq(w.consists.size(), 2, "two independent consists")

func test_no_coupling_across_unconnected_track() -> void:
	# A disconnected parallel siding 3 m away: dropping there must not couple
	# to the train on the main line.
	var w := _straight_world()
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(10, 3.0)), 10.0))
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 0.5))
	var res := TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), Vector2(11, 3.2))
	assert_true(bool(res.ok) and not bool(res.coupled), "siding drop stays separate")
	assert_eq(w.consists.size(), 2, "one train per track")

func test_coupled_center_distance_matches_placement() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(20, 0.5))
	var c: Consist = w.consists[0]
	var preview := c.path.pose_at_distance(
		TrainBuilder.coupled_center_distance(c, "back", 6.0)).origin
	TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), c.coupler_points().back + Vector2(-3.0, 0.3))
	var pls := c.car_placements()
	var actual: Vector2 = (pls[1].front + pls[1].back) * 0.5
	assert_vec_approx(actual, preview, "snap preview matches the real placement", 0.05)

# ---------- forgiving loop closure + path rebinding ----------

## A 360° ring built from 90° arcs, with the last one swept by `last_deg`
## (90 = exact closure, >90 overlaps the start, <90 leaves a gap).
func _ring_world(last_deg: float) -> World:
	var w := World.new()
	var pose := Transform2D.IDENTITY
	for _i in range(3):
		var e := ArcEdge.new(pose, 6.0, PI / 2.0)
		w.track.add_edge(e)
		pose = e.end_pose()
	w.track.add_edge(ArcEdge.new(pose, 6.0, deg_to_rad(last_deg)))
	return w

func test_overlapping_loop_still_loops() -> void:
	var w := _ring_world(120.0)   # closing piece overshoots the start by 30°
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	assert_true(path.is_loop, "overlapping ends close the loop")
	assert_approx(path.total_length(), TAU * 6.0, "overlap trimmed away", 0.15)
	var wrap := path.pose_at_distance(path.total_length() - 0.01).origin
	assert_vec_approx(wrap, path.pose_at_distance(0.0).origin, "seamless joint", 0.2)

func test_slightly_short_loop_still_loops() -> void:
	var w := _ring_world(85.0)   # ~0.5 m gap at the joint
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	assert_true(path.is_loop, "near-miss ends close the loop")

func test_train_keeps_running_through_sloppy_joint() -> void:
	var w := _ring_world(120.0)
	var placed := TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(1.0, 0.5))
	assert_true(bool(placed.ok), "engine placed on the ring")
	var c: Consist = w.consists[0]
	c.target_speed = 8.0
	for _i in range(30 * 60):
		w.tick(1.0 / 60.0)
	assert_true(c.velocity > 6.0, "still moving after many laps (v=%.2f)" % c.velocity)

func test_track_changed_rebinds_parked_train() -> void:
	# Train parked on an open 2-edge line; player then extends the line.
	var w := World.new()
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 10.0))
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(10, 0)), 10.0))
	TrainBuilder.place_vehicle(w, _def("e1", "engine", 8.0), Vector2(15, 0.5))
	var c: Consist = w.consists[0]
	var before: Vector2 = c.path.pose_at_distance(c.distance).origin
	w.track.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(20, 0)), 10.0))
	w.track_changed()
	assert_approx(c.path.total_length(), 30.0, "path now spans the new edge")
	assert_vec_approx(c.path.pose_at_distance(c.distance).origin, before,
		"train did not move when the track grew")

func test_unpowered_cars_do_not_move() -> void:
	var w := _straight_world()
	TrainBuilder.place_vehicle(w, _def("c1", "car", 6.0), Vector2(15, 0.5))
	var c: Consist = w.consists[0]
	c.target_speed = 8.0
	var d0 := c.distance
	for _i in range(120):
		c.tick(1.0 / 60.0)
	assert_approx(c.distance, d0, "no engine, no motion", 0.01)
