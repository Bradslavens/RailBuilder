extends TestCase
## BlockMap + World signal enforcement: signals split the network into blocks,
## trains refuse to enter a block occupied by another train.

func _line_world() -> World:
	# Three 10 m straights along +x (ids 1/2/3); nodes at x=10 and x=20.
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

func test_no_signals_one_block() -> void:
	var w := _line_world()
	var bm := w.blocks()
	assert_eq(bm.block_of[1], bm.block_of[2], "1+2 joined")
	assert_eq(bm.block_of[2], bm.block_of[3], "2+3 joined")

func test_signal_splits_blocks() -> void:
	var w := _line_world()
	assert_eq(w.toggle_signal_at(Vector2(20, 0.5)), "added", "signal placed at node")
	var bm := w.blocks()
	assert_eq(bm.block_of[1], bm.block_of[2], "1+2 still joined")
	assert_true(bm.block_of[2] != bm.block_of[3], "signal separates 3")

func test_toggle_removes_signal() -> void:
	var w := _line_world()
	w.toggle_signal_at(Vector2(20, 0.5))
	assert_eq(w.toggle_signal_at(Vector2(20.3, -0.4)), "removed", "second toggle removes")
	assert_eq(w.signals.size(), 0, "no signals left")

func test_no_node_in_range_is_noop() -> void:
	var w := _line_world()
	assert_eq(w.toggle_signal_at(Vector2(15, 8.0)), "", "far from any node")

func test_train_stops_before_occupied_block() -> void:
	var w := _line_world()
	w.toggle_signal_at(Vector2(20, 0.0))
	TrainBuilder.place_vehicle(w, _def("p", "engine", 8.0), Vector2(25, 0.5))   # parked in block 3
	TrainBuilder.place_vehicle(w, _def("m", "engine", 8.0), Vector2(5, 0.5))
	var mover: Consist = w.consists[1]
	mover.target_speed = 8.0
	for _i in range(15 * 60):
		w.tick(1.0 / 60.0)
	var front: Vector2 = mover.path.pose_at_distance(mover.distance).origin
	assert_true(front.x < 20.0, "stopped before the signal (at x=%.2f)" % front.x)
	assert_true(front.x > 16.0, "pulled up close to the signal (at x=%.2f)" % front.x)
	assert_approx(mover.velocity, 0.0, "standing", 0.05)

func test_train_proceeds_when_block_clears() -> void:
	var w := _line_world()
	w.toggle_signal_at(Vector2(20, 0.0))
	TrainBuilder.place_vehicle(w, _def("p", "engine", 8.0), Vector2(25, 0.5))
	TrainBuilder.place_vehicle(w, _def("m", "engine", 8.0), Vector2(5, 0.5))
	var parked: Consist = w.consists[0]
	var mover: Consist = w.consists[1]
	mover.target_speed = 8.0
	for _i in range(15 * 60):
		w.tick(1.0 / 60.0)
	w.consists.erase(parked)
	for _i in range(5 * 60):
		w.tick(1.0 / 60.0)
	var front: Vector2 = mover.path.pose_at_distance(mover.distance).origin
	assert_true(front.x > 20.0, "entered the block once clear (at x=%.2f)" % front.x)

func test_signal_states_three_aspect() -> void:
	# Signals at x=10 and x=20 -> blocks {1}, {2}, {3}.
	var w := _line_world()
	w.toggle_signal_at(Vector2(10, 0.0))
	w.toggle_signal_at(Vector2(20, 0.0))
	var states := w.signal_states()
	assert_eq(states.size(), 2, "two signals")
	assert_eq(String(states[0].state), "green", "all clear -> green")
	assert_eq(String(states[1].state), "green", "all clear -> green")

	TrainBuilder.place_vehicle(w, _def("p", "engine", 8.0), Vector2(25, 0.5))   # in block 3
	states = w.signal_states()
	# Signal at 10 guards block 2 (clear) but block 3 beyond it is occupied.
	assert_eq(String(states[0].state), "yellow", "next clear, next-next occupied -> yellow")
	# Signal at 20 guards block 3 (occupied).
	assert_eq(String(states[1].state), "red", "next block occupied -> red")
	assert_vec_approx(states[1].pos, Vector2(20, 0), "signal sits on its node")

func test_signal_not_red_for_its_own_approach_block() -> void:
	var w := _line_world()
	w.toggle_signal_at(Vector2(10, 0.0))
	TrainBuilder.place_vehicle(w, _def("p", "engine", 8.0), Vector2(5, 0.5))   # in block 1
	var states := w.signal_states()
	assert_eq(String(states[0].state), "green",
		"a train behind the signal doesn't redden it")
