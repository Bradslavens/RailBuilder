extends TestCase
## StraightEdge geometry.

func test_length() -> void:
	var e := StraightEdge.new(Transform2D.IDENTITY, 4.0)
	assert_approx(e.length(), 4.0, "length")

func test_pose_at_start_and_end() -> void:
	var e := StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0)
	assert_vec_approx(e.pose_at(0.0).origin, Vector2(0, 0), "start pos")
	assert_vec_approx(e.end_pose().origin, Vector2(4, 0), "end pos")
	assert_approx(e.end_pose().get_rotation(), 0.0, "end heading")

func test_pose_at_rotated() -> void:
	# Heading 90 deg -> forward is +y.
	var e := StraightEdge.new(Transform2D(PI / 2.0, Vector2(1, 1)), 2.0)
	assert_vec_approx(e.end_pose().origin, Vector2(1, 3), "rotated end pos")
	assert_approx(e.end_pose().get_rotation(), PI / 2.0, "heading preserved")

func test_midpoint() -> void:
	var e := StraightEdge.new(Transform2D(0.0, Vector2.ZERO), 4.0)
	assert_vec_approx(e.pose_at(2.0).origin, Vector2(2, 0), "midpoint")
