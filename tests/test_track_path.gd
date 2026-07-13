extends TestCase
## TrackPath: distance -> pose mapping across segments, reversed edges, and loops.

func _straight_path() -> TrackPath:
	var p := TrackPath.new()
	p.add_segment(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0), false)
	p.add_segment(StraightEdge.new(Transform2D(0.0, Vector2(4, 0)), 4.0), false)
	return p

func test_total_length() -> void:
	assert_approx(_straight_path().total_length(), 8.0, "total length")

func test_pose_spans_segments() -> void:
	var p := _straight_path()
	assert_vec_approx(p.pose_at_distance(0.0).origin, Vector2(0, 0), "d=0")
	assert_vec_approx(p.pose_at_distance(6.0).origin, Vector2(6, 0), "d=6 (2nd seg)")
	assert_approx(p.pose_at_distance(6.0).get_rotation(), 0.0, "heading forward")

func test_clamps_open_path() -> void:
	var p := _straight_path()
	assert_vec_approx(p.pose_at_distance(100.0).origin, Vector2(8, 0), "clamped to end")
	assert_vec_approx(p.pose_at_distance(-5.0).origin, Vector2(0, 0), "clamped to start")

func test_reversed_segment() -> void:
	# Edge (0,0)->(4,0) traversed reversed: enter at (4,0) heading ~180, exit at (0,0).
	var p := TrackPath.new()
	p.add_segment(StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0), true)
	assert_vec_approx(p.pose_at_distance(0.0).origin, Vector2(4, 0), "reversed entry")
	assert_vec_approx(p.pose_at_distance(4.0).origin, Vector2(0, 0), "reversed exit")
	var dir := Vector2.RIGHT.rotated(p.pose_at_distance(2.0).get_rotation())
	assert_vec_approx(dir, Vector2(-1, 0), "reversed heading points back")
