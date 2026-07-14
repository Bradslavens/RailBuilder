class_name Serializer
extends RefCounted
## Save/load for the simulation. Because the sim core holds no node references,
## a World round-trips cleanly through a plain Dictionary / JSON. Wired in from
## Phase 1 so persistence never has to be retrofitted.

static func edge_from_dict(d: Dictionary) -> TrackEdge:
	var origin := Transform2D(float(d.get("rot", 0.0)), Vector2(float(d.get("px", 0.0)), float(d.get("py", 0.0))))
	var e: TrackEdge = null
	match String(d.get("type", "")):
		"straight":
			e = StraightEdge.new(origin, float(d.get("len", 1.0)))
		"arc":
			e = ArcEdge.new(origin, float(d.get("radius", 1.0)), float(d.get("sweep", PI / 2.0)))
		_:
			return null
	e.id = int(d.get("id", -1))
	return e

static func world_from_dict(d: Dictionary) -> World:
	var w := World.new()
	var max_id := 0
	for ed in d.get("edges", []):
		var e := edge_from_dict(ed)
		if e != null:
			w.track.edges.append(e)
			max_id = maxi(max_id, e.id)
	w.track._next_id = max_id + 1
	var max_sig := 0
	for sd in d.get("signals", []):
		var sig := {"id": int(sd.get("id", 0)), "edge_id": int(sd.get("edge_id", -1)),
			"end": String(sd.get("end", "start"))}
		if w.track.get_edge(sig.edge_id) != null:
			w.signals.append(sig)
			max_sig = maxi(max_sig, sig.id)
	w._next_signal_id = max_sig + 1
	var terrain_dict: Dictionary = d.get("terrain", {})
	for key in terrain_dict:
		var parts := String(key).split(",")
		if parts.size() == 2:
			w.terrain[Vector2i(int(parts[0]), int(parts[1]))] = String(terrain_dict[key])
	# Absent in v2 saves, which simply load with no scenery.
	for sd in d.get("scenery", []):
		w.add_scenery({"id": int(sd.get("id", 0)), "model_id": String(sd.get("model_id", "")),
			"pos": Vector2(float(sd.get("x", 0.0)), float(sd.get("y", 0.0))),
			"rot": float(sd.get("rot", 0.0))})
	for cd in d.get("consists", []):
		var c := _consist_from_dict(cd, w.track)
		if c != null:
			w.consists.append(c)
	return w

## Rebuild a consist: the path is regenerated from its anchor edge/orientation
## (PathBuilder is deterministic), then cars and motion state are restored.
static func _consist_from_dict(d: Dictionary, track: TrackGraph) -> Consist:
	var anchor := track.get_edge(int(d.get("anchor_edge_id", -1)))
	if anchor == null:
		return null
	var c := Consist.new()
	c.anchor_edge_id = anchor.id
	c.anchor_reversed = bool(d.get("anchor_reversed", false))
	c.path = PathBuilder.build_from(track, anchor, c.anchor_reversed)
	c.distance = float(d.get("distance", 0.0))
	c.velocity = float(d.get("velocity", 0.0))
	c.target_speed = float(d.get("target_speed", 0.0))
	c.autopilot = bool(d.get("autopilot", true))
	for card in d.get("cars", []):
		var car := Car.new(float(card.get("length_m", 8.0)), float(card.get("mass_kg", 20000.0)),
			String(card.get("kind", "car")))
		car.model_id = StringName(String(card.get("model_id", "")))
		car.health = float(card.get("health", 100.0))
		c.cars.append(car)
	return c if not c.cars.is_empty() else null

static func save_to_file(w: World, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(w.to_dict(), "\t"))
	f.close()
	return OK

static func load_from_file(path: String) -> World:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return world_from_dict(parsed)
