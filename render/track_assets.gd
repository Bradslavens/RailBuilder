class_name TrackAssets
extends RefCounted
## Maps sim TrackEdges to the GLB track models in Assets/Tracks and builds posed
## 3D nodes for them. Models are loaded at runtime via GLTFDocument (same path in
## editor and exported builds; user-provided GLBs need no editor import) and cached.
##
## Model contract (matches the shipped Track_*.glb set): the piece's Entry sits at
## the model origin facing -Z, and a node named "*_Exit" marks the far end. Curves
## are radius 6; the straight tile is 2 m. Sim sweep > 0 (CCW on the 2D plane)
## becomes a right-hand bend when lifted onto XZ, hence the R/L flip.

const DIR := "res://Assets/Tracks"
const STRAIGHT_TILE_M := 2.0
const RADIUS := 6.0
const ANGLES := [30.0, 45.0, 90.0]
const EPS := 0.01

static var _scene_cache: Dictionary = {}

## The GLB that renders this edge, or "" when no model matches its geometry
## (caller should fall back to the procedural TrackMeshBuilder).
static func model_path(edge: TrackEdge) -> String:
	if edge is StraightEdge:
		return DIR + "/Track_Straight.glb"
	if edge is ArcEdge:
		if absf(edge.radius - RADIUS) > EPS:
			return ""
		var deg := rad_to_deg(absf(edge.sweep))
		for a in ANGLES:
			if absf(deg - a) <= EPS:
				var side := "R" if edge.sweep > 0.0 else "L"
				return "%s/Track_Curve%d%s.glb" % [DIR, int(a), side]
	return ""

## Load (and cache) a track GLB; returns a fresh copy to add to the scene.
static func load_model(path: String) -> Node3D:
	if not _scene_cache.has(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			_scene_cache[path] = null
		else:
			_scene_cache[path] = doc.generate_scene(state)
	var proto: Node3D = _scene_cache[path]
	return null if proto == null else proto.duplicate()

## The Exit marker's transform in model space (identity if the model lacks one).
static func model_exit_transform(path: String) -> Transform3D:
	var model := load_model(path)
	if model == null:
		return Transform3D.IDENTITY
	var out := Transform3D.IDENTITY
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and n.name.ends_with("_Exit"):
			out = n.transform
			break
		for c in n.get_children():
			stack.append(c)
	model.free()
	return out

## Build a posed Node3D rendering the edge, or null when no model matches.
## Straights are tiled with 2 m pieces; a partial remainder is z-scaled to fit.
static func build_edge_node(edge: TrackEdge, y: float = 0.0) -> Node3D:
	var path := model_path(edge)
	if path == "":
		return null
	if edge is ArcEdge:
		var inst := load_model(path)
		if inst == null:
			return null
		inst.transform = Geo3D.pose_transform(edge.start_pose(), y)
		return inst
	var holder := Node3D.new()
	holder.name = "StraightTiles"
	var s := 0.0
	while s < edge.length() - EPS:
		var tile := load_model(path)
		if tile == null:
			holder.free()
			return null
		var t := Geo3D.pose_transform(edge.pose_at(s), y)
		var run := minf(STRAIGHT_TILE_M, edge.length() - s)
		if run < STRAIGHT_TILE_M - EPS:
			t.basis = t.basis * Basis.from_scale(Vector3(1, 1, run / STRAIGHT_TILE_M))
		tile.transform = t
		holder.add_child(tile)
		s += STRAIGHT_TILE_M
	return holder
