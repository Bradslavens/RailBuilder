class_name TrackPath
extends RefCounted
## An ordered walk of oriented track edges — the "wire" a train rides along.
##
## Each segment references a TrackEdge and whether it is traversed reversed (from
## its end back to its start). pose_at_distance maps a single scalar arc-length to
## a world pose, wrapping for loops and clamping for open paths. Everything about
## train motion and car placement is expressed in this 1-D distance coordinate.

var segments: Array = []   # each: {edge: TrackEdge, reversed: bool, len: float}
var is_loop: bool = false

var _total: float = 0.0

## seg_len < edge.length() rides only the first part of the edge (in traversal
## direction) — used to close loops whose final piece overlaps the start.
func add_segment(edge: TrackEdge, reversed: bool, seg_len: float = -1.0) -> void:
	var l := edge.length() if seg_len < 0.0 else clampf(seg_len, 0.0, edge.length())
	segments.append({"edge": edge, "reversed": reversed, "len": l})
	_total += l

## Shorten the last segment to new_len (traversal meters). See PathBuilder.
func trim_last(new_len: float) -> void:
	var seg: Dictionary = segments[segments.size() - 1]
	var l := clampf(new_len, 0.0, float(seg.len))
	_total += l - float(seg.len)
	seg.len = l

## Drop the last segment entirely.
func pop_last() -> void:
	_total -= float(segments[segments.size() - 1].len)
	segments.pop_back()

func total_length() -> float:
	return _total

## World pose at arc-length d along the path.
func pose_at_distance(d: float) -> Transform2D:
	if segments.is_empty():
		return Transform2D.IDENTITY
	if is_loop and _total > 0.0:
		d = fposmod(d, _total)
	else:
		d = clampf(d, 0.0, _total)
	for i in range(segments.size()):
		var seg = segments[i]
		if d <= seg.len or i == segments.size() - 1:
			return _seg_pose(seg, clampf(d, 0.0, seg.len))
		d -= seg.len
	return Transform2D.IDENTITY

func _seg_pose(seg: Dictionary, local: float) -> Transform2D:
	var e: TrackEdge = seg.edge
	if seg.reversed:
		var p := e.pose_at(e.length() - local)
		return Transform2D(p.get_rotation() + PI, p.origin)
	return e.pose_at(local)

## Path distance of the point at edge-local arc-length s on edge_id, or -1.0 if
## that edge is not part of this path. This ties path space (per-consist) to edge
## space (shared by all consists), which coupling/signals/collisions rely on.
func distance_of(edge_id: int, s: float) -> float:
	var base := 0.0
	for seg in segments:
		var e := seg.edge as TrackEdge
		if e.id == edge_id:
			var local: float = (e.length() - s) if seg.reversed else s
			return base + clampf(local, 0.0, float(seg.len))
		base += seg.len
	return -1.0

## The edge point under path distance d: {edge_id, s, reversed} (s edge-local).
## Inverse of distance_of; used to re-anchor trains when the track is edited.
func locate(d: float) -> Dictionary:
	if segments.is_empty():
		return {}
	if is_loop and _total > 0.0:
		d = fposmod(d, _total)
	else:
		d = clampf(d, 0.0, _total)
	for i in range(segments.size()):
		var seg = segments[i]
		if d <= seg.len or i == segments.size() - 1:
			var local := clampf(d, 0.0, float(seg.len))
			var e := seg.edge as TrackEdge
			return {"edge_id": e.id, "s": (e.length() - local) if seg.reversed else local,
				"reversed": bool(seg.reversed)}
		d -= seg.len
	return {}

## Map the path interval [d0, d1] to per-edge intervals [{edge_id, a, b}] with
## a < b in edge-local arc-length. Wraps on loops, clamps on open paths. This is
## how a train's footprint is expressed in shared coordinates.
func map_interval(d0: float, d1: float) -> Array:
	var out := []
	if segments.is_empty() or _total <= 0.0 or d1 <= d0:
		return out
	var spans: Array[Vector2] = []
	if is_loop:
		var span_len := minf(d1 - d0, _total)
		var start := fposmod(d0, _total)
		if start + span_len <= _total:
			spans.append(Vector2(start, start + span_len))
		else:
			spans.append(Vector2(start, _total))
			spans.append(Vector2(0.0, start + span_len - _total))
	else:
		spans.append(Vector2(clampf(d0, 0.0, _total), clampf(d1, 0.0, _total)))
	var base := 0.0
	for seg in segments:
		for sp in spans:
			var lo := maxf(sp.x, base)
			var hi := minf(sp.y, base + seg.len)
			if hi - lo > 0.0001:
				var a := lo - base
				var b := hi - base
				if seg.reversed:
					# Edge-local s runs opposite to traversal (from the edge's end).
					var el := (seg.edge as TrackEdge).length()
					var t := a
					a = el - b
					b = el - t
				out.append({"edge_id": (seg.edge as TrackEdge).id, "a": a, "b": b})
		base += seg.len
	return out
