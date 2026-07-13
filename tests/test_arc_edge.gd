extends TestCase
## ArcEdge geometry. Left = CCW (sweep > 0), right = CW (sweep < 0).

func test_quarter_left() -> void:
	var e := ArcEdge.new(Transform2D(0.0, Vector2.ZERO), 1.0, PI / 2.0)
	assert_approx(e.length(), PI / 2.0, "arc length")
	var ep := e.end_pose()
	assert_vec_approx(ep.origin, Vector2(1, 1), "left quarter end pos")
	assert_approx(ep.get_rotation(), PI / 2.0, "left quarter end heading")

func test_quarter_right() -> void:
	var e := ArcEdge.new(Transform2D(0.0, Vector2.ZERO), 1.0, -PI / 2.0)
	var ep := e.end_pose()
	assert_vec_approx(ep.origin, Vector2(1, -1), "right quarter end pos")
	assert_approx(ep.get_rotation(), -PI / 2.0, "right quarter end heading")

func test_midpoint_on_circle() -> void:
	# Halfway around a left unit quarter-circle centered at (0,1): 45 deg point.
	var e := ArcEdge.new(Transform2D(0.0, Vector2.ZERO), 1.0, PI / 2.0)
	var mid := e.pose_at(e.length() * 0.5)
	assert_vec_approx(mid.origin, Vector2(0.7071, 0.2929), "45-degree midpoint")
	assert_approx(mid.get_rotation(), PI / 4.0, "45-degree heading")

func test_start_pose_is_origin() -> void:
	var e := ArcEdge.new(Transform2D(0.0, Vector2(3, 5)), 2.0, PI / 3.0)
	assert_vec_approx(e.start_pose().origin, Vector2(3, 5), "start at origin")
