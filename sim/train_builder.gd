class_name TrainBuilder
extends RefCounted
## Player-driven train assembly: place engines and cars directly on the track.
##
## A vehicle dropped near an existing consist's end coupler snaps onto that train
## (front or back); anywhere else on the track it starts a new one-car consist.
## Placement that would overlap another train is rejected. Cars can be removed
## again — pulling one out of the middle splits the consist in two.
##
## Pure sim logic: operates on World/ModelDef, no engine or UI references.

const PLACE_RANGE := 3.0      # max meters from track for a drop to count
const COUPLE_RANGE := 2.5     # drop within this of a consist end -> couple
const SAMPLE_STEP := 0.25     # arc-length sampling for nearest-point queries

## Nearest point on any edge to p: {edge, s, dist, pose}, or {} on empty track.
static func nearest_track_point(graph: TrackGraph, p: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for e in graph.edges:
		var n := maxi(2, int(ceil(e.length() / SAMPLE_STEP)))
		for i in range(n + 1):
			var s := e.length() * float(i) / float(n)
			var pose := e.pose_at(s)
			var d := pose.origin.distance_to(p)
			if d < best_d:
				best_d = d
				best = {"edge": e, "s": s, "dist": d, "pose": pose}
	return best

## The consist end a drop at p would couple onto: {consist, end: "front"|"back"},
## or {} if none. The capture radius includes half the new car's length, because
## the player clicks where the car's BODY should sit — which is half a car back
## from the coupler. Only trains on the same track as the click can couple.
static func couple_target(world: World, car_length: float, p: Vector2) -> Dictionary:
	var hit := nearest_track_point(world.track, p)
	if hit.is_empty() or float(hit.dist) > PLACE_RANGE + car_length:
		return {}
	var hit_edge_id: int = (hit.edge as TrackEdge).id
	var hit_s := float(hit.s)
	var best := {}
	var best_d := COUPLE_RANGE + car_length * 0.5
	for c in world.consists:
		if c.path == null or c.cars.is_empty():
			continue
		if c.path.distance_of(hit_edge_id, hit_s) < 0.0:
			continue   # a train on some other, unconnected track
		var cp := c.coupler_points()
		var d_back: float = p.distance_to(cp.back)
		var d_front: float = p.distance_to(cp.front)
		if d_back < best_d:
			best_d = d_back
			best = {"consist": c, "end": "back"}
		if d_front < best_d:
			best_d = d_front
			best = {"consist": c, "end": "front"}
	return best

## Path distance of the center of a car_length car coupled at that end — where
## the car will actually sit. Used for placement and the editor's snap preview.
static func coupled_center_distance(c: Consist, end: String, car_length: float) -> float:
	if end == "front":
		return c.distance + Consist.COUPLER_GAP + car_length * 0.5
	return c.distance - c.total_length() - Consist.COUPLER_GAP - car_length * 0.5

## Place a vehicle at p. Returns {ok, coupled, consist} ({ok: false} if p is too
## far from track, the track is too short, or the spot is blocked by a train).
## flipped reverses the travel direction of a newly started consist.
static func place_vehicle(world: World, def: ModelDef, p: Vector2, flipped: bool = false) -> Dictionary:
	# Near an existing train's end? Snap onto that consist.
	var tgt := couple_target(world, def.length_m, p)
	if not tgt.is_empty():
		var c: Consist = tgt.consist
		if String(tgt.end) == "back":
			c.cars.append(_car_from_def(def))
		else:
			c.cars.insert(0, _car_from_def(def))
			c.distance += def.length_m + Consist.COUPLER_GAP
		return {"ok": true, "coupled": true, "consist": c}

	var hit := nearest_track_point(world.track, p)
	if hit.is_empty() or float(hit.dist) > PLACE_RANGE:
		return {"ok": false}
	var path := full_path(world.track, hit.edge, flipped)
	if path.total_length() < def.length_m:
		return {"ok": false}
	var c := Consist.new()
	c.path = path
	c.anchor_edge_id = (path.segments[0].edge as TrackEdge).id
	c.anchor_reversed = bool(path.segments[0].reversed)
	c.autopilot = true
	c.target_speed = 0.0
	c.cars.append(_car_from_def(def))
	c.distance = path.distance_of((hit.edge as TrackEdge).id, float(hit.s)) + def.length_m * 0.5
	if path.is_loop:
		c.distance = fposmod(c.distance, path.total_length())
	else:
		c.distance = clampf(c.distance, def.length_m, path.total_length())
	# Reject drops on top of another train.
	for other in world.consists:
		if overlap_len(c.occupied_intervals(), other.occupied_intervals()) > 0.001:
			return {"ok": false}
	world.consists.append(c)
	return {"ok": true, "coupled": false, "consist": c}

## Remove the car nearest p (within range). End cars pop off; removing a middle
## car splits the consist in two. Returns {ok, split}.
static func remove_car_at(world: World, p: Vector2, range_m: float = 2.0) -> Dictionary:
	var best_c: Consist = null
	var best_i := -1
	var best_d := range_m
	for c in world.consists:
		var pls := c.car_placements()
		for i in range(pls.size()):
			var mid: Vector2 = (pls[i].front + pls[i].back) * 0.5
			var d := p.distance_to(mid)
			if d < best_d:
				best_d = d
				best_c = c
				best_i = i
	if best_c == null:
		return {"ok": false}
	if best_c.cars.size() == 1:
		world.consists.erase(best_c)
		return {"ok": true, "split": false}
	if best_i == 0:
		best_c.distance -= best_c.cars[0].length_m + Consist.COUPLER_GAP
		best_c.cars.remove_at(0)
		return {"ok": true, "split": false}
	if best_i == best_c.cars.size() - 1:
		best_c.cars.remove_at(best_i)
		return {"ok": true, "split": false}
	# Middle car: the front half keeps this consist, the rear becomes a new one.
	var offset := 0.0
	for j in range(best_i + 1):
		offset += best_c.cars[j].length_m + Consist.COUPLER_GAP
	var rear := Consist.new()
	rear.path = best_c.path
	rear.anchor_edge_id = best_c.anchor_edge_id
	rear.anchor_reversed = best_c.anchor_reversed
	rear.autopilot = true
	rear.target_speed = 0.0
	rear.distance = best_c.distance - offset
	for j in range(best_i + 1, best_c.cars.size()):
		rear.cars.append(best_c.cars[j])
	best_c.cars.resize(best_i)
	world.consists.append(rear)
	return {"ok": true, "split": true}

## The complete path through touch_edge traveling in its natural direction
## (or flipped). PathBuilder only walks forward, so on open lines we walk
## backward first and rebuild from the far end — a train placed mid-line can
## then grow couplers in both directions.
static func full_path(graph: TrackGraph, touch_edge: TrackEdge, flipped: bool) -> TrackPath:
	var fwd := PathBuilder.build_from(graph, touch_edge, flipped)
	if fwd.is_loop:
		return fwd
	var back := PathBuilder.build_from(graph, touch_edge, not flipped)
	var last: Dictionary = back.segments[back.segments.size() - 1]
	return PathBuilder.build_from(graph, last.edge, not bool(last.reversed))

## Total overlapping length between two per-edge interval sets (0 = disjoint).
static func overlap_len(ia: Array, ib: Array) -> float:
	var total := 0.0
	for a in ia:
		for b in ib:
			if a.edge_id == b.edge_id:
				total += maxf(0.0, minf(a.b, b.b) - maxf(a.a, b.a))
	return total

static func _car_from_def(def: ModelDef) -> Car:
	var kind := "engine" if def.category == "engine" else "car"
	var car := Car.new(def.length_m, def.mass_kg, kind)
	car.model_id = def.id
	return car
