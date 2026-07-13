extends TestCase
## PieceCatalog: data-driven piece construction and previews.

func test_make_straight() -> void:
	var e := PieceCatalog.make_def({"type": "straight", "len": 5.0}, Transform2D.IDENTITY)
	assert_true(e is StraightEdge, "straight type")
	assert_approx(e.length(), 5.0, "straight length")

func test_make_arc_left_positive_sweep() -> void:
	var e := PieceCatalog.make_def({"type": "arc", "radius": 6.0, "deg": 90.0}, Transform2D.IDENTITY)
	assert_true(e is ArcEdge, "arc type")
	assert_approx(e.length(), 6.0 * PI / 2.0, "quarter-circle length", 0.001)
	assert_true(e.end_pose().origin.y > 0.0, "left turn curves to +y")

func test_make_arc_right_negative_sweep() -> void:
	var e := PieceCatalog.make_def({"type": "arc", "radius": 6.0, "deg": -90.0}, Transform2D.IDENTITY)
	assert_true(e.end_pose().origin.y < 0.0, "right turn curves to -y")

func test_catalog_is_straight_plus_three_curves() -> void:
	assert_eq(PieceCatalog.PIECES.size(), 4, "straight + 30/45/90")
	var ids := {}
	for d in PieceCatalog.PIECES:
		ids[str(d.get("id", ""))] = true
	for want in ["straight", "curve30", "curve45", "curve90"]:
		assert_true(ids.has(want), "has piece %s" % want)
	for d in PieceCatalog.PIECES:
		var pts := PieceCatalog.preview_points(d, 8)
		assert_true(pts.size() >= 3, "preview points for %s" % str(d.get("id", "?")))

func test_mirror_flips_curve_direction() -> void:
	# Flipping the sign of deg mirrors left <-> right (as the editor's flip does).
	var left := PieceCatalog.make_def({"type": "arc", "radius": 6.0, "deg": 45.0}, Transform2D.IDENTITY)
	var right := PieceCatalog.make_def({"type": "arc", "radius": 6.0, "deg": -45.0}, Transform2D.IDENTITY)
	assert_true(left.end_pose().origin.y > 0.0 and right.end_pose().origin.y < 0.0, "mirror reverses turn")

func test_rotated_origin_sets_start_heading() -> void:
	# The editor places un-snapped pieces using a rotation; make_def honors it.
	var e := PieceCatalog.make_def({"type": "straight", "len": 4.0}, Transform2D(PI / 2.0, Vector2.ZERO))
	assert_approx(e.start_pose().get_rotation(), PI / 2.0, "start heading follows rotation")
