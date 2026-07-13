extends TestCase
## PathBuilder: connectivity walk, loop detection, dead-end handling.

func _loop_graph() -> TrackGraph:
	# Four 90-degree arcs chained into a full circle (radius 5).
	var g := TrackGraph.new()
	var o := Transform2D(0.0, Vector2.ZERO)
	for _i in range(4):
		var a := ArcEdge.new(o, 5.0, PI / 2.0)
		g.add_edge(a)
		o = a.end_pose()
	return g

func test_builds_closed_loop() -> void:
	var g := _loop_graph()
	var path := PathBuilder.build_from(g, g.edges[0])
	assert_true(path.is_loop, "detects closed loop")
	assert_eq(path.segments.size(), 4, "four segments")
	assert_approx(path.total_length(), TAU * 5.0, "circumference = 2*pi*r", 0.01)

func test_open_chain_is_not_loop() -> void:
	var g := TrackGraph.new()
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(4, 0)), 4.0))
	var path := PathBuilder.build_from(g, g.edges[0])
	assert_true(not path.is_loop, "open chain is not a loop")
	assert_eq(path.segments.size(), 2, "two segments")
	assert_approx(path.total_length(), 8.0, "chain length")
