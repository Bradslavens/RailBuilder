class_name PathBuilder
extends RefCounted
## Builds a TrackPath by walking edge connectivity from a starting edge, following
## the network until it returns to the start (closed loop) or hits a dead end.
##
## Phase 2 assumes simple chains/loops (no switch branching); at a junction it takes
## the first matching continuation. Switch-aware routing arrives in Phase 4.

const TOL := 0.25        # meters, endpoint coincidence
const JOIN_TOL := 0.8    # meters, sloppy loop-closure forgiveness

static func build_from(graph: TrackGraph, start: TrackEdge, start_reversed: bool = false) -> TrackPath:
	var path := TrackPath.new()
	if start == null:
		return path
	var current := start
	var reversed := start_reversed
	var guard := graph.edges.size() + 1
	while guard > 0:
		guard -= 1
		path.add_segment(current, reversed)
		var ex_pos := _exit_pos(current, reversed)
		var nxt := _find_next(graph, current, ex_pos)
		if nxt.is_empty():
			_try_close_loop(path)
			break
		if nxt.edge == start:
			path.is_loop = true
			break
		current = nxt.edge
		reversed = nxt.reversed
	return path

## Forgiving loop closure for hand-built layouts: if the walk dead-ends but the
## last piece passes near (or overlaps past) the path's starting point, trim the
## last segment at its closest approach and call it a loop. The train then rides
## through the joint instead of stopping at a not-quite-connected end.
static func _try_close_loop(path: TrackPath) -> void:
	if path.segments.size() < 2:
		return
	var start_pos: Vector2 = path.pose_at_distance(0.0).origin
	var seg: Dictionary = path.segments[path.segments.size() - 1]
	var best_t := -1.0
	var best_d := JOIN_TOL
	var steps := maxi(4, int(ceil(float(seg.len) / 0.1)))
	for i in range(steps + 1):
		var t := float(seg.len) * float(i) / float(steps)
		var d := _seg_sample(seg, t).distance_to(start_pos)
		if d < best_d:
			best_d = d
			best_t = t
	if best_t < 0.0:
		return
	if best_t <= 0.05:
		path.pop_last()   # the whole last piece overlaps past the start
	else:
		path.trim_last(best_t)
	path.is_loop = true

## Position at traversal-distance t along a segment (t=0 at its entry point).
static func _seg_sample(seg: Dictionary, t: float) -> Vector2:
	var e: TrackEdge = seg.edge
	if seg.reversed:
		return e.pose_at(e.length() - t).origin
	return e.pose_at(t).origin

static func _exit_pos(edge: TrackEdge, reversed: bool) -> Vector2:
	return edge.start_pose().origin if reversed else edge.end_pose().origin

## Returns {edge, reversed} for the next edge continuing from exit_pos, or {} if none.
static func _find_next(graph: TrackGraph, current: TrackEdge, exit_pos: Vector2) -> Dictionary:
	for e in graph.edges:
		if e == current:
			continue
		if e.start_pose().origin.distance_to(exit_pos) <= TOL:
			return {"edge": e, "reversed": false}
		if e.end_pose().origin.distance_to(exit_pos) <= TOL:
			return {"edge": e, "reversed": true}
	return {}
