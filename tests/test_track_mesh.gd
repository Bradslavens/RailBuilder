extends TestCase
## TrackMeshBuilder: array generation and mesh assembly.

func test_straight_vertex_and_index_counts() -> void:
	# length 4 / step 0.5 -> 8 spans -> 9 samples; 3 strips (bed + 2 rails).
	var e := StraightEdge.new(Transform2D.IDENTITY, 4.0)
	var a := TrackMeshBuilder.build_arrays([e])
	# 9 samples * 2 verts/sample * 3 strips = 54
	assert_eq(a.vertices.size(), 54, "vertex count")
	# 8 spans * 6 indices * 3 strips = 144
	assert_eq(a.indices.size(), 144, "index count")
	assert_eq(a.colors.size(), a.vertices.size(), "one color per vertex")

func test_indices_in_range() -> void:
	var e := ArcEdge.new(Transform2D.IDENTITY, 6.0, PI / 3.0)
	var a := TrackMeshBuilder.build_arrays([e])
	var vcount: int = a.vertices.size()
	var maxi_seen := 0
	for i in a.indices:
		maxi_seen = maxi(maxi_seen, i)
	assert_true(maxi_seen < vcount, "no index out of bounds")

func test_bed_and_rail_heights() -> void:
	var e := StraightEdge.new(Transform2D.IDENTITY, 2.0)
	var a := TrackMeshBuilder.build_arrays([e])
	var ys := {}
	for v in a.vertices:
		ys[snappedf(v.y, 0.001)] = true
	assert_true(ys.has(TrackMeshBuilder.BED_Y), "bed height present")
	assert_true(ys.has(TrackMeshBuilder.RAIL_Y), "rail height present")

func test_build_mesh_has_one_surface() -> void:
	var e := StraightEdge.new(Transform2D.IDENTITY, 4.0)
	var mesh := TrackMeshBuilder.build_mesh([e])
	assert_eq(mesh.get_surface_count(), 1, "single combined surface")

func test_empty_edges_yield_empty_mesh() -> void:
	var mesh := TrackMeshBuilder.build_mesh([])
	assert_eq(mesh.get_surface_count(), 0, "no edges -> no surface")
