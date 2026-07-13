class_name TrackGraph
extends RefCounted
## The rail network: a collection of TrackEdges plus endpoint/snapping queries.
##
## Kept deliberately free of any engine (Node) references so it can be simulated
## headlessly, unit-tested, and serialized. Two endpoints that share a position
## are considered "connected"; anything unconnected is an "open" endpoint that a
## new piece can snap onto.

const SNAP_POS_TOL := 0.25   # meters
const SNAP_ANG_TOL := 0.20   # radians

var edges: Array[TrackEdge] = []
var _next_id: int = 1

func add_edge(edge: TrackEdge) -> TrackEdge:
	edge.id = _next_id
	_next_id += 1
	edges.append(edge)
	return edge

func get_edge(edge_id: int) -> TrackEdge:
	for e in edges:
		if e.id == edge_id:
			return e
	return null

## Every endpoint of every edge as {pose, edge_id, end}.
func _all_endpoints() -> Array:
	var eps := []
	for e in edges:
		eps.append({"pose": e.start_pose(), "edge_id": e.id, "end": "start"})
		eps.append({"pose": e.end_pose(), "edge_id": e.id, "end": "end"})
	return eps

## Endpoints not coincident with any other endpoint — i.e. free to connect to.
func open_endpoints() -> Array:
	var eps := _all_endpoints()
	var open := []
	for i in range(eps.size()):
		var connected := false
		for j in range(eps.size()):
			if i == j:
				continue
			if eps[i].pose.origin.distance_to(eps[j].pose.origin) <= SNAP_POS_TOL:
				connected = true
				break
		if not connected:
			open.append(eps[i])
	return open

## Find the nearest open endpoint to a candidate start pose.
## Returns {snapped: bool, pose: Transform2D, endpoint: Dictionary}.
func find_snap(candidate_start: Transform2D) -> Dictionary:
	var best = null
	var best_d := SNAP_POS_TOL
	for ep in open_endpoints():
		var d: float = candidate_start.origin.distance_to(ep.pose.origin)
		if d <= best_d:
			best_d = d
			best = ep
	if best == null:
		return {"snapped": false, "pose": candidate_start}
	return {"snapped": true, "pose": best.pose, "endpoint": best}
