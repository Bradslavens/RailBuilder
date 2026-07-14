class_name World
extends RefCounted
## Top-level simulation state. Advanced by GameState's fixed-timestep tick loop.
##
## Everything gameplay-relevant hangs off this object and is serializable. It holds
## NO references to scene nodes; the 2D editor and 3D view are read-only consumers.
##
## Per tick: recompute block occupancy from every train's footprint, set each
## train's signal stop distance, advance the trains, then resolve collisions.

const SIGNAL_LOOKAHEAD := 60.0   # meters scanned ahead for red signals
const SIGNAL_STANDOFF := 0.5     # stop this far before the signal node

var track: TrackGraph = TrackGraph.new()
var consists: Array[Consist] = []
var signals: Array[Dictionary] = []   # {id, edge_id, end("start"|"end")}
var terrain: Dictionary = {}          # Vector2i cell -> terrain type id (String)
var scenery: Array[Dictionary] = []   # {id, model_id (String), pos (Vector2), rot (float)}

var _next_signal_id: int = 1
var _next_scenery_id: int = 1
var _blocks: BlockMap = null
var _blocks_dirty: bool = true

# Consist pairs currently in contact (managed by Collisions, kept here so it
# survives across ticks; damage applies once per new contact).
var colliding_pairs: Dictionary = {}

## Advance the simulation by one fixed tick. Deterministic-ready: no frame-time
## or rendering state should influence anything here.
func tick(dt: float) -> void:
	var occ := occupancy()
	for c in consists:
		c.stop_in = _signal_stop_distance(c, occ)
	for c in consists:
		c.tick(dt)
	Collisions.resolve(self)

## Call after any track or signal mutation so blocks get rebuilt.
func invalidate_blocks() -> void:
	_blocks_dirty = true

## Call after track geometry changes: rebuilds blocks AND re-anchors every
## train's path — so a train parked on a line starts looping the moment the
## player closes the circle, and can run onto newly added track.
func track_changed() -> void:
	invalidate_blocks()
	rebuild_consist_paths()

## Rebuild each consist's path from the edge currently under its front, keeping
## its world position and direction of travel.
func rebuild_consist_paths() -> void:
	for c in consists:
		if c.path == null or c.path.segments.is_empty() or c.cars.is_empty():
			continue
		var loc := c.path.locate(c.distance)
		if loc.is_empty():
			continue
		var edge := track.get_edge(int(loc.edge_id))
		if edge == null:
			continue   # the edge under the train was deleted; keep the old path
		var p := TrainBuilder.full_path(track, edge, bool(loc.reversed))
		var nd := p.distance_of(edge.id, float(loc.s))
		if nd < 0.0:
			continue
		c.path = p
		c.distance = nd
		c.anchor_edge_id = (p.segments[0].edge as TrackEdge).id
		c.anchor_reversed = bool(p.segments[0].reversed)

func blocks() -> BlockMap:
	if _blocks_dirty or _blocks == null:
		_blocks = BlockMap.build(track, signals)
		_blocks_dirty = false
	return _blocks

# ---------- signals ----------

## Add or remove a signal at the track node nearest p. Returns "added",
## "removed", or "" (no node in range).
func toggle_signal_at(p: Vector2, max_dist: float = 2.5) -> String:
	var node := blocks().nearest_node(p, max_dist)
	if node.is_empty():
		return ""
	for s in signals:
		var sn := blocks().node_of_signal(s)
		if not sn.is_empty() and (sn.pos as Vector2).distance_to(node.pos) <= BlockMap.NODE_TOL:
			signals.erase(s)
			invalidate_blocks()
			return "removed"
	var anchor: Dictionary = node.endpoints[0]
	signals.append({"id": _next_signal_id, "edge_id": int(anchor.edge_id), "end": String(anchor.end)})
	_next_signal_id += 1
	invalidate_blocks()
	return "added"

## Rendering info for every signal: {id, pos, state: "green"|"yellow"|"red"}.
## Three-aspect, judged in the signal's facing direction (away from its
## anchoring edge): red = the next block is occupied, yellow = the next block
## is clear but the one after it is occupied, green = both clear.
func signal_states() -> Array:
	var out := []
	var occ := occupancy()
	var bm := blocks()
	for s in signals:
		var node := bm.node_of_signal(s)
		if node.is_empty():
			continue
		var approach: int = bm.block_of.get(int(s.edge_id), -1)
		var next_block := -1
		for ep in node.endpoints:
			var b: int = bm.block_of.get(int(ep.edge_id), -1)
			if b != approach:
				next_block = b
				break
		var state := "green"
		if next_block >= 0:
			if occ.has(next_block):
				state = "red"
			else:
				for b2 in _blocks_beyond(bm, next_block, node):
					if occ.has(b2):
						state = "yellow"
		out.append({"id": int(s.id), "pos": node.pos, "state": state})
	return out

## Blocks reachable from `block` through OTHER signal nodes (block boundaries
## only exist at signals). Used for the yellow aspect's two-block lookahead.
func _blocks_beyond(bm: BlockMap, block: int, via_node: Dictionary) -> Array:
	var out := []
	for n in bm.nodes:
		if not n.has_signal or n == via_node:
			continue
		var touches := false
		var others := []
		for ep in n.endpoints:
			var b: int = bm.block_of.get(int(ep.edge_id), -1)
			if b == block:
				touches = true
			elif b >= 0 and not others.has(b):
				others.append(b)
		if touches:
			out.append_array(others)
	return out

## block index -> Array[Consist] currently touching it.
func occupancy() -> Dictionary:
	var occ := {}
	var bm := blocks()
	for c in consists:
		for iv in c.occupied_intervals():
			var b: int = bm.block_of.get(int(iv.edge_id), -1)
			if b < 0:
				continue
			if not occ.has(b):
				occ[b] = []
			if not (occ[b] as Array).has(c):
				occ[b].append(c)
	return occ

## Meters ahead of c's front where it must stop for a red signal (INF = clear).
## A signal is "red" for c when the block just beyond it holds another train.
func _signal_stop_distance(c: Consist, occ: Dictionary) -> float:
	if c.path == null or signals.is_empty():
		return INF
	var bm := blocks()
	var total := c.path.total_length()
	var stop := INF
	for s in signals:
		var e := track.get_edge(int(s.edge_id))
		if e == null:
			continue
		var ds := c.path.distance_of(e.id, 0.0 if String(s.end) == "start" else e.length())
		if ds < 0.0:
			continue
		var ahead := ds - c.distance
		if c.path.is_loop:
			ahead = fposmod(ahead, total)
		if ahead <= 0.05 or ahead > SIGNAL_LOOKAHEAD:
			continue
		# The block on the far side of the crossing is what the signal guards.
		var beyond := c.path.map_interval(ds + 0.02, ds + 0.4)
		if beyond.is_empty():
			continue
		var entered: int = bm.block_of.get(int(beyond[0].edge_id), -1)
		var current := c.path.map_interval(ds - 0.4, ds - 0.02)
		if not current.is_empty() and bm.block_of.get(int(current[0].edge_id), -1) == entered:
			continue   # signal doesn't separate blocks along this path
		if occ.has(entered):
			for other in occ[entered]:
				if other != c:
					stop = minf(stop, maxf(ahead - SIGNAL_STANDOFF, 0.0))
	return stop

# ---------- terrain ----------

## Paint (or, with type_id == "", erase) one terrain cell.
func paint_terrain(cell: Vector2i, type_id: String) -> void:
	if type_id == "":
		terrain.erase(cell)
	else:
		terrain[cell] = type_id

# ---------- scenery ----------

## Place a scenery model (mountains, trees, buildings) anywhere on the map. Unlike
## rolling stock, scenery is not track-bound and the tick loop never reads it: it is
## decoration that both views render from the same data. Returns the new entry.
func place_scenery(model_id: StringName, pos: Vector2, rot: float = 0.0) -> Dictionary:
	var s := {"id": _next_scenery_id, "model_id": String(model_id), "pos": pos, "rot": rot}
	_next_scenery_id += 1
	scenery.append(s)
	return s

## Re-add an existing entry, keeping its id (undo/redo and load).
func add_scenery(s: Dictionary) -> void:
	scenery.append(s)
	_next_scenery_id = maxi(_next_scenery_id, int(s.get("id", 0)) + 1)

## Remove by id. Returns the removed entry, or {} if there was no such id.
func remove_scenery(id: int) -> Dictionary:
	for i in range(scenery.size()):
		if int(scenery[i].id) == id:
			return scenery.pop_at(i)
	return {}

func to_dict() -> Dictionary:
	var edge_dicts := []
	for e in track.edges:
		edge_dicts.append(e.to_dict())
	var sig_dicts := []
	for s in signals:
		sig_dicts.append({"id": int(s.id), "edge_id": int(s.edge_id), "end": String(s.end)})
	var terrain_dict := {}
	for cell in terrain:
		terrain_dict["%d,%d" % [cell.x, cell.y]] = String(terrain[cell])
	var scenery_dicts := []
	for s in scenery:
		var p: Vector2 = s.pos
		scenery_dicts.append({"id": int(s.id), "model_id": String(s.model_id),
			"x": p.x, "y": p.y, "rot": float(s.rot)})
	var consist_dicts := []
	for c in consists:
		var car_dicts := []
		for car in c.cars:
			car_dicts.append({"length_m": car.length_m, "mass_kg": car.mass_kg,
				"kind": car.kind, "model_id": String(car.model_id), "health": car.health})
		consist_dicts.append({
			"anchor_edge_id": c.anchor_edge_id, "anchor_reversed": c.anchor_reversed,
			"distance": c.distance, "velocity": c.velocity,
			"target_speed": c.target_speed, "autopilot": c.autopilot,
			"cars": car_dicts,
		})
	return {
		"version": 3,
		"edges": edge_dicts,
		"signals": sig_dicts,
		"terrain": terrain_dict,
		"scenery": scenery_dicts,
		"consists": consist_dicts,
	}
