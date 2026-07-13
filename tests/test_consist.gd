extends TestCase
## Consist: longitudinal physics and car placement along a path.

func _loop_path() -> TrackPath:
	var g := TrackGraph.new()
	var o := Transform2D(0.0, Vector2.ZERO)
	for _i in range(4):
		var a := ArcEdge.new(o, 5.0, PI / 2.0)
		g.add_edge(a)
		o = a.end_pose()
	return PathBuilder.build_from(g, g.edges[0])

func test_accelerates_under_throttle() -> void:
	var c := Consist.new()
	c.path = _loop_path()
	c.autopilot = false
	c.throttle = 1.0
	for _i in range(30):
		c.tick(0.1)   # 3 seconds
	assert_true(c.velocity > 1.0, "throttle builds speed")
	assert_true(c.distance > 0.0, "train moves forward")

func test_wraps_within_loop() -> void:
	var c := Consist.new()
	c.path = _loop_path()
	c.autopilot = false
	c.throttle = 1.0
	for _i in range(2000):
		c.tick(0.1)
	assert_true(c.distance >= 0.0 and c.distance < c.path.total_length(), "distance stays within loop")

func test_brake_stops_without_reversing() -> void:
	var c := Consist.new()
	c.path = _loop_path()
	c.autopilot = false
	c.velocity = 10.0
	c.brake = 1.0
	for _i in range(200):
		c.tick(0.1)
	assert_approx(c.velocity, 0.0, "brakes to a stop", 0.2)

func test_autopilot_reaches_target_speed() -> void:
	var c := Consist.new()
	c.path = _loop_path()
	c.cars.append(Car.new(9.0, 40000.0, "engine"))   # traction needs an engine
	c.autopilot = true
	c.target_speed = 6.0
	for _i in range(600):
		c.tick(0.05)
	assert_approx(c.velocity, 6.0, "cruises at target speed", 0.5)

func test_car_placements() -> void:
	var c := Consist.demo(_loop_path())
	var pl := c.car_placements()
	assert_eq(pl.size(), 4, "engine + 3 cars")
	assert_eq(pl[0].kind, "engine", "first car is the engine")
	var head := c.path.pose_at_distance(c.distance).origin
	assert_vec_approx(pl[0].front, head, "lead car front at train head", 0.02)
	# Each car body has non-zero length on the path.
	var body_len: float = pl[0].front.distance_to(pl[0].back)
	assert_true(body_len > 1.0, "car body spans a real length")
