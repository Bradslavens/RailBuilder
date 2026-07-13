class_name TrackMeshBuilder
extends RefCounted
## Generates 3D track geometry by extruding a fixed cross-section (a ballast bed plus
## two rails) along each edge's parametric curve, sampling pose_at(s). Returns plain
## vertex arrays (testable headlessly) and a convenience ArrayMesh wrapper.

const BED_HALF := 1.30      # half-width of the ballast bed (m)
const BED_Y := 0.02
const RAIL_HALF := 0.075    # half-width of a rail head (m)
const RAIL_OFFSET := 0.7175 # rail centerline from track center (~standard gauge)
const RAIL_Y := 0.15
const SAMPLE_STEP := 0.5    # meters between cross-sections

const BED_COLOR := Color(0.28, 0.26, 0.24)
const RAIL_COLOR := Color(0.62, 0.64, 0.70)

## Build raw mesh arrays for a list of TrackEdges.
static func build_arrays(edges: Array) -> Dictionary:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for e in edges:
		var samples := _sample_edge(e)
		_add_strip(verts, norms, cols, idx, samples, 0.0, BED_HALF, BED_Y, BED_COLOR)
		_add_strip(verts, norms, cols, idx, samples, -RAIL_OFFSET, RAIL_HALF, RAIL_Y, RAIL_COLOR)
		_add_strip(verts, norms, cols, idx, samples, RAIL_OFFSET, RAIL_HALF, RAIL_Y, RAIL_COLOR)
	return {"vertices": verts, "normals": norms, "colors": cols, "indices": idx}

## Build a renderable ArrayMesh (vertex colors as albedo).
static func build_mesh(edges: Array) -> ArrayMesh:
	var a := build_arrays(edges)
	var mesh := ArrayMesh.new()
	if a.vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a.vertices
	arrays[Mesh.ARRAY_NORMAL] = a.normals
	arrays[Mesh.ARRAY_COLOR] = a.colors
	arrays[Mesh.ARRAY_INDEX] = a.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _sample_edge(e: TrackEdge) -> Array:
	var n := maxi(2, int(ceil(e.length() / SAMPLE_STEP)))
	var out := []
	for i in range(n + 1):
		var s := e.length() * float(i) / float(n)
		var p := e.pose_at(s)
		out.append({
			"c": Vector3(p.origin.x, 0.0, p.origin.y),
			"r": Geo3D.right_of(p.get_rotation()),
		})
	return out

static func _add_strip(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, samples: Array, offset: float, hw: float, y: float, color: Color) -> void:
	var up := Vector3.UP
	var base := verts.size()
	for sm in samples:
		verts.append(sm.c + sm.r * (offset - hw) + up * y)
		verts.append(sm.c + sm.r * (offset + hw) + up * y)
		norms.append(up)
		norms.append(up)
		cols.append(color)
		cols.append(color)
	for i in range(samples.size() - 1):
		var i0 := base + i * 2
		idx.append(i0); idx.append(i0 + 1); idx.append(i0 + 3)
		idx.append(i0); idx.append(i0 + 3); idx.append(i0 + 2)
