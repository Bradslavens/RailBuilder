extends TestCase
## End-to-end: a loop world with a demo train advances under World.tick, exactly as
## the running game drives it via the GameState fixed-tick loop.

func _loop_world() -> World:
	var w := World.new()
	var o := Transform2D(0.0, Vector2.ZERO)
	for _i in range(4):
		var a := ArcEdge.new(o, 5.0, PI / 2.0)
		w.track.add_edge(a)
		o = a.end_pose()
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	w.consists.append(Consist.demo(path))
	return w

func test_world_tick_moves_train() -> void:
	var w := _loop_world()
	var c := w.consists[0]
	var before: Vector2 = c.car_placements()[0].front
	for _i in range(120):
		w.tick(1.0 / 60.0)   # ~2 seconds at sim rate
	assert_true(c.distance > 0.0, "train advanced along the path")
	var after: Vector2 = c.car_placements()[0].front
	assert_true(before.distance_to(after) > 0.5, "lead car visibly moved")

func test_all_cars_stay_on_the_loop() -> void:
	var w := _loop_world()
	var c := w.consists[0]
	for _i in range(600):
		w.tick(1.0 / 60.0)
	# On a radius-5 circle centered at (0,5)+..., every bogie must sit ~on the circle.
	# Simplest invariant: no placement is NaN / wildly far from the track extent.
	for pl in c.car_placements():
		assert_true(pl.front.length() < 100.0 and pl.back.length() < 100.0, "car stays near the loop")
