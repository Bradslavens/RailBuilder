class_name BlockMap
extends RefCounted
## Factorio-style signal blocks. The track graph's nodes (clusters of coincident
## edge endpoints) either join their edges into one block or — when a player has
## placed a signal on that node — act as a block boundary. Trains refuse to enter
## a block occupied by another train (see World), so signals carve the network
## into safe sections.

const NODE_TOL := 0.25   # meters, endpoint coincidence (matches TrackGraph)

## Node clusters: {pos: Vector2, endpoints: Array of {edge_id, end}, has_signal: bool}
var nodes: Array = []
## edge_id -> block index. Edges in the same block share an index.
var block_of: Dictionary = {}

## Build from the current track + signal list ({edge_id, end} dictionaries).
static func build(graph: TrackGraph, signals: Array) -> BlockMap:
	var bm := BlockMap.new()
	bm._cluster_nodes(graph, signals)
	bm._union_blocks(graph)
	return bm

func _cluster_nodes(graph: TrackGraph, signals: Array) -> void:
	nodes.clear()
	for e in graph.edges:
		_add_endpoint(e.start_pose().origin, e.id, "start")
		_add_endpoint(e.end_pose().origin, e.id, "end")
	for n in nodes:
		n.has_signal = false
		for s in signals:
			for ep in n.endpoints:
				if int(ep.edge_id) == int(s.edge_id) and String(ep.end) == String(s.end):
					n.has_signal = true

func _add_endpoint(pos: Vector2, edge_id: int, end: String) -> void:
	for n in nodes:
		if (n.pos as Vector2).distance_to(pos) <= NODE_TOL:
			n.endpoints.append({"edge_id": edge_id, "end": end})
			return
	nodes.append({"pos": pos, "endpoints": [{"edge_id": edge_id, "end": end}], "has_signal": false})

func _union_blocks(graph: TrackGraph) -> void:
	var parent := {}
	for e in graph.edges:
		parent[e.id] = e.id
	for n in nodes:
		if n.has_signal:
			continue   # boundary: edges meeting here stay in separate blocks
		var first := -1
		for ep in n.endpoints:
			if first < 0:
				first = int(ep.edge_id)
			else:
				_union(parent, first, int(ep.edge_id))
	block_of.clear()
	for e in graph.edges:
		block_of[e.id] = _find(parent, e.id)

func _find(parent: Dictionary, x: int) -> int:
	while int(parent[x]) != x:
		parent[x] = parent[int(parent[x])]
		x = int(parent[x])
	return x

func _union(parent: Dictionary, a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)

## Nearest node to p within max_dist, or an empty Dictionary.
func nearest_node(p: Vector2, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for n in nodes:
		var d := (n.pos as Vector2).distance_to(p)
		if d <= best_d:
			best_d = d
			best = n
	return best

## The node a signal sits on (matched by its anchoring endpoint), or empty.
func node_of_signal(sig: Dictionary) -> Dictionary:
	for n in nodes:
		for ep in n.endpoints:
			if int(ep.edge_id) == int(sig.edge_id) and String(ep.end) == String(sig.end):
				return n
	return {}
