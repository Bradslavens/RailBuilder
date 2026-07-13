extends TestCase
## TrackGraph: id assignment, open-endpoint detection, and snapping.

func test_add_assigns_unique_ids() -> void:
	var g := TrackGraph.new()
	var a := g.add_edge(StraightEdge.new(Transform2D.IDENTITY, 4.0))
	var b := g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(4, 0)), 4.0))
	assert_true(a.id != b.id, "unique ids")
	assert_true(a.id > 0 and b.id > 0, "positive ids")

func test_single_edge_has_two_open_ends() -> void:
	var g := TrackGraph.new()
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	assert_eq(g.open_endpoints().size(), 2, "one edge -> 2 open ends")

func test_chained_edges_share_a_connection() -> void:
	var g := TrackGraph.new()
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2(4, 0)), 4.0))
	# The two pieces meet at (4,0); only the far ends remain open.
	assert_eq(g.open_endpoints().size(), 2, "two chained edges -> 2 open ends")

func test_find_snap_hits_nearby_endpoint() -> void:
	var g := TrackGraph.new()
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	var res := g.find_snap(Transform2D(0.0, Vector2(4.1, 0.05)))
	assert_true(res.snapped, "should snap near (4,0)")
	assert_vec_approx(res.pose.origin, Vector2(4, 0), "snap adopts endpoint pose")

func test_find_snap_misses_when_far() -> void:
	var g := TrackGraph.new()
	g.add_edge(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0))
	var res := g.find_snap(Transform2D(0.0, Vector2(50, 50)))
	assert_true(not res.snapped, "far away -> no snap")
