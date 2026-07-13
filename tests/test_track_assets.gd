extends TestCase
## TrackAssets: maps sim TrackEdges to the GLB track models in Assets/Tracks and
## builds correctly-posed 3D nodes for them. The alignment tests prove the GLB
## geometry agrees with the parametric edges the snapping/sim run on.

const EPS := 0.01

# ---- model mapping ----

func test_straight_maps_to_straight_model() -> void:
	var e := StraightEdge.new(Transform2D.IDENTITY, 6.0)
	assert_eq(TrackAssets.model_path(e), "res://Assets/Tracks/Track_Straight.glb", "straight model")

func test_arc_mapping_covers_catalog_angles_and_sides() -> void:
	# sweep > 0 (CCW in sim plane) lifts to a right-hand bend in 3D (XZ mirror).
	for deg in [30.0, 45.0, 90.0]:
		var pos := ArcEdge.new(Transform2D.IDENTITY, 6.0, deg_to_rad(deg))
		var neg := ArcEdge.new(Transform2D.IDENTITY, 6.0, -deg_to_rad(deg))
		assert_eq(TrackAssets.model_path(pos), "res://Assets/Tracks/Track_Curve%dR.glb" % int(deg), "+%s -> R" % deg)
		assert_eq(TrackAssets.model_path(neg), "res://Assets/Tracks/Track_Curve%dL.glb" % int(deg), "-%s -> L" % deg)

func test_unknown_geometry_maps_to_nothing() -> void:
	var odd := ArcEdge.new(Transform2D.IDENTITY, 6.0, deg_to_rad(60.0))
	assert_eq(TrackAssets.model_path(odd), "", "60 deg arc has no model")
	var odd_r := ArcEdge.new(Transform2D.IDENTITY, 4.0, deg_to_rad(90.0))
	assert_eq(TrackAssets.model_path(odd_r), "", "radius 4 arc has no model")

# ---- pose lifting ----

func test_pose_transform_identity_heading_faces_plus_x() -> void:
	# 2D heading 0 = +x forward; model forward is -Z, so -Z must map onto +X.
	var t := Geo3D.pose_transform(Transform2D.IDENTITY)
	assert_approx((t.basis * Vector3.FORWARD).x, 1.0, "forward lifts to +X", EPS)
	assert_approx(t.origin.length(), 0.0, "origin at 0", EPS)

func test_pose_transform_places_origin_on_xz() -> void:
	var t := Geo3D.pose_transform(Transform2D(0.0, Vector2(3.0, -2.0)), 0.5)
	assert_approx(t.origin.x, 3.0, "x", EPS)
	assert_approx(t.origin.y, 0.5, "y offset", EPS)
	assert_approx(t.origin.z, -2.0, "sim y -> z", EPS)

# ---- GLB alignment: entry transform * model Exit == lifted end_pose ----

func test_curve_glb_exits_match_parametric_end_poses() -> void:
	for deg in [30.0, 45.0, 90.0]:
		for sgn in [1.0, -1.0]:
			var e := ArcEdge.new(Transform2D(0.7, Vector2(5.0, 3.0)), 6.0, sgn * deg_to_rad(deg))
			var exit := TrackAssets.model_exit_transform(TrackAssets.model_path(e))
			var world_exit: Transform3D = Geo3D.pose_transform(e.start_pose()) * exit
			var want: Transform3D = Geo3D.pose_transform(e.end_pose())
			var tag := "%s%s" % [deg, "R" if sgn > 0 else "L"]
			assert_approx((world_exit.origin - want.origin).length(), 0.0, "exit pos %s" % tag, EPS)
			var fwd_got := world_exit.basis * Vector3.FORWARD
			var fwd_want := want.basis * Vector3.FORWARD
			assert_approx(fwd_got.dot(fwd_want), 1.0, "exit heading %s" % tag, EPS)

func test_straight_glb_is_two_meters() -> void:
	var exit := TrackAssets.model_exit_transform("res://Assets/Tracks/Track_Straight.glb")
	assert_approx(exit.origin.z, -2.0, "straight exit 2 m along -Z", EPS)

# ---- node building ----

func test_straight_edge_tiles_every_two_meters() -> void:
	var node := TrackAssets.build_edge_node(StraightEdge.new(Transform2D.IDENTITY, 6.0))
	assert_true(node != null, "node built")
	assert_eq(node.get_child_count(), 3, "6 m straight = 3 tiles")
	node.free()

func test_short_straight_scales_last_tile() -> void:
	var node := TrackAssets.build_edge_node(StraightEdge.new(Transform2D.IDENTITY, 3.0))
	assert_eq(node.get_child_count(), 2, "3 m = full tile + partial")
	var last := node.get_child(1) as Node3D
	assert_approx(last.transform.basis.z.length(), 0.5, "partial tile z-scaled to 1 m", EPS)
	node.free()

func test_curve_edge_builds_single_instance() -> void:
	var node := TrackAssets.build_edge_node(ArcEdge.new(Transform2D.IDENTITY, 6.0, deg_to_rad(90.0)))
	assert_true(node != null, "node built")
	node.free()

func test_unknown_edge_builds_nothing() -> void:
	var node := TrackAssets.build_edge_node(ArcEdge.new(Transform2D.IDENTITY, 4.0, 1.0))
	assert_true(node == null, "no node for unmapped geometry")
