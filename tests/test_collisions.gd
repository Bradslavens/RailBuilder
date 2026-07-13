extends TestCase
## Collision resolution: overlapping trains stop, take speed-based damage on
## first contact, get separated bumper-to-bumper, and never die.

func _line_world() -> World:
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
	return d

func _crash_world() -> World:
	# No signals: the mover plows into the parked train.
	var w := _line_world()
	TrainBuilder.place_vehicle(w, _def("p", "engine", 8.0), Vector2(25, 0.5))
	TrainBuilder.place_vehicle(w, _def("m", "engine", 8.0), Vector2(5, 0.5))
	(w.consists[1] as Consist).target_speed = 8.0
	for _i in range(15 * 60):
		w.tick(1.0 / 60.0)
	return w

func test_crash_stops_both_and_damages() -> void:
	var w := _crash_world()
	var parked: Consist = w.consists[0]
	var mover: Consist = w.consists[1]
	assert_approx(mover.velocity, 0.0, "mover stopped", 0.01)
	assert_approx(mover.target_speed, 0.0, "crash cancels the run order", 0.01)
	assert_true(mover.cars[0].health < 100.0, "mover damaged")
	assert_true(parked.cars[0].health < 100.0, "parked train damaged")
	assert_true(mover.cars[0].health >= Car.MIN_HEALTH, "never dies")
	# Bumper to bumper: mover front just short of parked back (x = 21).
	var front: Vector2 = mover.path.pose_at_distance(mover.distance).origin
	assert_true(front.x < 21.0 and front.x > 19.5, "separated at contact point (x=%.2f)" % front.x)

func test_no_repeat_damage_while_touching() -> void:
	var w := _crash_world()
	var h: float = (w.consists[1] as Consist).cars[0].health
	for _i in range(5 * 60):
		w.tick(1.0 / 60.0)
	assert_approx((w.consists[1] as Consist).cars[0].health, h, "one hit, one damage")

func test_damaged_train_is_slower() -> void:
	var w := _line_world()
	TrainBuilder.place_vehicle(w, _def("m", "engine", 8.0), Vector2(5, 0.5))
	var c: Consist = w.consists[0]
	c.cars[0].health = 30.0
	c.target_speed = 8.0
	for _i in range(10 * 60):
		w.tick(1.0 / 60.0)
	assert_true(c.velocity < 4.0, "limps at reduced speed (v=%.2f)" % c.velocity)
	assert_true(c.velocity > 1.0, "still runs (v=%.2f)" % c.velocity)

func test_gentle_bump_no_damage() -> void:
	var w := _line_world()
	TrainBuilder.place_vehicle(w, _def("p", "engine", 8.0), Vector2(20, 0.5))
	TrainBuilder.place_vehicle(w, _def("m", "engine", 8.0), Vector2(7, 0.5))   # beyond couple range
	var mover: Consist = w.consists[1]
	mover.target_speed = 0.9   # below the damage threshold
	for _i in range(30 * 60):
		w.tick(1.0 / 60.0)
	assert_approx(mover.cars[0].health, 100.0, "slow bump is free")
	assert_approx((w.consists[0] as Consist).cars[0].health, 100.0, "parked unharmed")
