extends Control
## Build mode map: the top-down editor canvas. Sits beside the AssetDock (see
## editor_shell.gd) which supplies the active tool; track pieces can also be
## dragged from the dock straight onto the map.
##
## Tools (picked in the dock):
##   piece    click to place track (snaps to open endpoints, green rings)
##   vehicle  click near track to place an engine/car; near a train's end
##            coupler it snaps onto that train. X removes the car under the
##            cursor (middle car -> the train splits in two)
##   signal   click a track joint to place/remove a block signal
##   paint    click/drag to paint terrain squares (Erase clears)
##
## Trains are drawn with real top-down renders of their GLB models. Run starts
## and stops all trains; signals hold them out of occupied blocks; collisions
## damage cars (never fatal) and park both trains.
##
## Other controls:
##   Right click  deselect tool      Right drag  pan     Wheel  zoom
##   1..9 quick-select pieces        Q/E rotate  R rotate 45   F flip/direction
##   Ctrl+Z undo  Ctrl+Y redo        Del remove last piece     X remove car
##   S save   L load   Space run/stop   Tab 3D ride

## Emitted whenever the active tool changes so the dock stays in sync.
signal tool_changed(tool: Dictionary)

const BASE_PPM := 32.0
const SAVE_PATH := "user://layout.json"
const ROT_STEP := deg_to_rad(15.0)
# Zooming all the way out has to fit scenery, which dwarfs track: the mountain
# range is 143 m wide, where the old 0.25 floor showed barely 110 m of map.
const ZOOM_MIN := 0.08
const ZOOM_MAX := 6.0

const RAIL_OFFSET_M := 0.7175   # matches TrackMeshBuilder / the GLB gauge
const TIE_HALF_M := 1.0
const TIE_SPACING_M := 0.8
const CAR_HALF_W := 1.25        # meters, box-fallback rendering

var _cam_world: Vector2 = Vector2.ZERO   # world point shown at screen center
var _zoom: float = 1.0
var _mouse_world: Vector2 = Vector2.ZERO

var _tool: Dictionary = {}               # active dock tool ({} = none)
var _drag_piece: int = -1                # track piece under an active drag
var _ghost_rot: float = 0.0              # placement heading for un-snapped pieces
var _ghost_mirror: bool = false          # flip curves / vehicle direction
var _pan_moved: bool = false             # right-drag panned (suppresses deselect)
var _painting: bool = false              # LMB held with the paint tool

var _status: Label
var _run_button: Button
var _undo_button: Button
var _redo_button: Button

# Undo/redo: each entry is {op: "add"|"remove", edge: TrackEdge}.
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

## Off-screen renderer (owned by the shell) and the top-down sprite cache.
var thumbs: ThumbnailRenderer
var _sprites: Dictionary = {}            # model_id -> {texture, span_m}
var _sprites_requested: Dictionary = {}

## Shared model registry, injected by the editor shell (built lazily if the map
## runs standalone).
var library: ModelLibrary

func _ready() -> void:
	clip_contents = true   # never draw over the asset dock beside us
	_build_toolbar()
	_build_status_bar()
	_update_status()
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _sim() -> World:
	return GameState.world

func _lib() -> ModelLibrary:
	if library == null:
		library = ModelLibrary.build_default()
	return library

## Current view size, with a fallback in case layout hasn't run yet.
func _view_size() -> Vector2:
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		s = get_viewport_rect().size
	return s

# ---------- toolbar ----------

func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.name = "Toolbar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = 8
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	bar.add_child(hb)

	_tool_button(hb, "Save", "Save layout  (S)", _save)
	_tool_button(hb, "Load", "Load layout  (L)", _load)
	_tool_sep(hb)
	_undo_button = _tool_button(hb, "Undo", "Undo place/delete  (Ctrl+Z)", _undo_action)
	_redo_button = _tool_button(hb, "Redo", "Redo  (Ctrl+Y)", _redo_action)
	_tool_sep(hb)
	_run_button = _tool_button(hb, "Run", "Run / stop all trains  (Space)", _toggle_run)
	_tool_sep(hb)
	_tool_button(hb, "3D Ride", "Ride the layout in 3D  (Tab)", _go_3d)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	var hint := Label.new()
	hint.text = "wheel zoom · right-drag pan · Q/E rotate · F flip · X remove car"
	AppTheme.style_section_label(hint)
	hb.add_child(hint)
	add_child(bar)

func _tool_button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _tool_sep(parent: Control) -> void:
	var s := VSeparator.new()
	s.modulate = Color(1, 1, 1, 0.25)
	parent.add_child(s)

func _go_3d() -> void:
	get_tree().change_scene_to_file.call_deferred("res://views/ride3d/ride3d.tscn")

# ---------- status bar ----------

func _build_status_bar() -> void:
	var panel := PanelContainer.new()
	panel.name = "StatusBar"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 8
	panel.offset_top = -36
	panel.offset_bottom = -8
	_status = Label.new()
	panel.add_child(_status)
	add_child(panel)

func _tool_label() -> String:
	match _tool.get("kind", ""):
		"piece":
			return str(PieceCatalog.PIECES[int(_tool.index)].get("label", "?"))
		"vehicle", "scenery":
			var def := _lib().get_def(StringName(String(_tool.id)))
			return def.display_name if def != null else "?"
		"signal":
			return "Block Signal"
		"paint":
			var t := TerrainCatalog.get_type(String(_tool.type))
			return str(t.get("label", "Erase"))
	return "—"

func _update_status() -> void:
	if _status == null:
		return
	var rot_deg := int(round(rad_to_deg(_ghost_rot))) % 360
	var flip := "  ·  flipped" if _ghost_mirror else ""
	_status.text = "Tool: %s  ·  rot %d°%s  ·  zoom %.1fx  ·  trains %d  ·  %s" % [
		_tool_label(), rot_deg, flip, _zoom, _sim().consists.size(),
		"running" if _any_running() else "stopped"]
	if _run_button != null:
		_run_button.text = "Stop" if _any_running() else "Run"
	if _undo_button != null:
		_undo_button.disabled = _undo.is_empty()
		_redo_button.disabled = _redo.is_empty()

# ---------- tool selection (driven by the asset dock and shortcuts) ----------

func select_tool(tool: Dictionary) -> void:
	_tool = tool
	tool_changed.emit(_tool)
	_update_status()
	queue_redraw()

func _select_piece(index: int) -> void:
	select_tool({"kind": "piece", "index": index} if index >= 0 else {})

# ---------- coordinate transforms ----------

func _ppm() -> float:
	return BASE_PPM * _zoom

func _to_screen(world_m: Vector2) -> Vector2:
	return (world_m - _cam_world) * _ppm() + _view_size() * 0.5

func _to_world(screen_px: Vector2) -> Vector2:
	return (screen_px - _view_size() * 0.5) / _ppm() + _cam_world

# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_world = _to_world(event.position)
		# Pan with a held right button (no middle button needed) or middle drag.
		if event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			_cam_world -= event.relative / _ppm()
			if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_pan_moved = true
		elif _painting and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_paint_at(_mouse_world)
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_apply_tool(_to_world(event.position))
				MOUSE_BUTTON_RIGHT:
					_pan_moved = false
				MOUSE_BUTTON_WHEEL_UP:
					_zoom_at(event.position, 1.1)
				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom_at(event.position, 1.0 / 1.1)
		else:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_painting = false
			elif event.button_index == MOUSE_BUTTON_RIGHT and not _pan_moved:
				select_tool({})   # right-click without dragging deselects
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc: int = event.keycode
	if event.ctrl_pressed:
		match kc:
			KEY_Z:
				_redo_action() if event.shift_pressed else _undo_action()
			KEY_Y:
				_redo_action()
		_update_status()
		queue_redraw()
		return
	if kc >= KEY_1 and kc <= KEY_9:
		var idx := kc - KEY_1
		if idx < PieceCatalog.PIECES.size():
			_select_piece(idx)
		return
	match kc:
		KEY_Q: _ghost_rot -= ROT_STEP
		KEY_E: _ghost_rot += ROT_STEP
		KEY_R: _ghost_rot += deg_to_rad(45.0)
		KEY_F: _ghost_mirror = not _ghost_mirror
		KEY_EQUAL, KEY_KP_ADD: _zoom_at(_view_size() * 0.5, 1.15)
		KEY_MINUS, KEY_KP_SUBTRACT: _zoom_at(_view_size() * 0.5, 1.0 / 1.15)
		KEY_S: _save()
		KEY_L: _load()
		KEY_DELETE, KEY_BACKSPACE: _delete_last()
		KEY_X: _remove_car()
		KEY_SPACE: _toggle_run()
		KEY_TAB: _go_3d()
	_update_status()
	queue_redraw()

func _zoom_at(screen_px: Vector2, factor: float) -> void:
	var before := _to_world(screen_px)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var after := _to_world(screen_px)
	_cam_world += before - after
	_update_status()
	queue_redraw()

# ---------- drag-and-drop (native) ----------

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.get("type", "") == "track_piece":
		_drag_piece = int(data.get("index", -1))
		_mouse_world = _to_world(at_position)
		queue_redraw()
		return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var idx := int(data.get("index", -1))
	_drag_piece = -1
	_select_piece(idx)
	_place_piece(_to_world(at_position), idx)

# ---------- tool application ----------

func _apply_tool(world_m: Vector2) -> void:
	match _tool.get("kind", ""):
		"piece":
			_place_piece(world_m, int(_tool.index))
		"vehicle":
			_place_vehicle(world_m)
		"scenery":
			_place_scenery(world_m)
		"signal":
			if _sim().toggle_signal_at(world_m) != "":
				queue_redraw()
		"paint":
			_painting = true
			_paint_at(world_m)
	_update_status()

func _place_vehicle(world_m: Vector2) -> void:
	var def := _lib().get_def(StringName(String(_tool.get("id", ""))))
	if def == null:
		return
	var res := TrainBuilder.place_vehicle(_sim(), def, world_m, _ghost_mirror)
	if not bool(res.ok):
		return
	queue_redraw()

## Scenery drops wherever you click, free of the track, at the ghost's heading.
func _place_scenery(world_m: Vector2) -> void:
	var def := _lib().get_def(StringName(String(_tool.get("id", ""))))
	if def == null:
		return
	var s := _sim().place_scenery(def.id, world_m, _ghost_rot)
	_undo.append({"op": "add_scenery", "scenery": s})
	_redo.clear()
	queue_redraw()

## The topmost scenery model whose footprint covers world_m ({} if none). The sim
## stores only a position, so the footprint comes from the model's own size here.
func _scenery_at(world_m: Vector2) -> Dictionary:
	var items := _sim().scenery
	for i in range(items.size() - 1, -1, -1):
		var def := _lib().get_def(StringName(String(items[i].model_id)))
		if def == null:
			continue
		if (world_m - (items[i].pos as Vector2)).length() <= def.length_m * 0.5:
			return items[i]
	return {}

func _remove_car() -> void:
	if bool(TrainBuilder.remove_car_at(_sim(), _mouse_world).ok):
		_update_status()
		queue_redraw()
		return
	var s := _scenery_at(_mouse_world)
	if not s.is_empty():
		_sim().remove_scenery(int(s.id))
		_undo.append({"op": "remove_scenery", "scenery": s})
		_redo.clear()
		_update_status()
		queue_redraw()

func _paint_at(world_m: Vector2) -> void:
	if _tool.get("kind", "") != "paint":
		return
	_sim().paint_terrain(TerrainCatalog.cell_of(world_m), String(_tool.type))
	queue_redraw()

# ---------- track piece placement ----------

## The piece index to preview/place right now (active drag wins over the tool).
func _current_piece() -> int:
	if _drag_piece >= 0:
		return _drag_piece
	if _tool.get("kind", "") == "piece":
		return int(_tool.index)
	return -1

## Placement pose plus whether it snapped to an open endpoint.
func _snapped_pose(world_m: Vector2) -> Dictionary:
	var base := Transform2D(_ghost_rot, world_m)
	var snap := _sim().track.find_snap(base)
	return {"pose": snap.pose if snap.snapped else base, "snapped": snap.snapped}

## Build the concrete edge for a piece, applying the flip (mirror) to curves.
func _edge_for(index: int, pose: Transform2D) -> TrackEdge:
	var d: Dictionary = PieceCatalog.PIECES[index].duplicate()
	if _ghost_mirror and d.get("type", "") == "arc":
		d["deg"] = -float(d.get("deg", 0.0))
	return PieceCatalog.make_def(d, pose)

func _place_piece(world_m: Vector2, index: int) -> void:
	if index < 0 or index >= PieceCatalog.PIECES.size():
		return
	var edge := _edge_for(index, _snapped_pose(world_m).pose)
	if edge != null:
		_sim().track.add_edge(edge)
		_sim().track_changed()
		_undo.append({"op": "add", "edge": edge})
		_redo.clear()
	_update_status()
	queue_redraw()

func _delete_last() -> void:
	var edges := _sim().track.edges
	if edges.size() > 0:
		var e: TrackEdge = edges[edges.size() - 1]
		edges.remove_at(edges.size() - 1)
		_sim().track_changed()
		_undo.append({"op": "remove", "edge": e})
		_redo.clear()
	_update_status()

# ---------- undo / redo ----------

func _undo_action() -> void:
	if _undo.is_empty():
		return
	var a: Dictionary = _undo.pop_back()
	_apply_inverse(a)
	_redo.append(a)
	_update_status()
	queue_redraw()

func _redo_action() -> void:
	if _redo.is_empty():
		return
	var a: Dictionary = _redo.pop_back()
	_apply(a)
	_undo.append(a)
	_update_status()
	queue_redraw()

func _apply(a: Dictionary) -> void:
	match a.op:
		"add":
			_sim().track.edges.append(a.edge)
		"remove":
			_sim().track.edges.erase(a.edge)
		"add_scenery":
			_sim().add_scenery(a.scenery)
			return       # scenery is not track: no rebuild needed
		"remove_scenery":
			_sim().remove_scenery(int(a.scenery.id))
			return
	_sim().track_changed()

func _apply_inverse(a: Dictionary) -> void:
	match a.op:
		"add":
			_sim().track.edges.erase(a.edge)
		"remove":
			_sim().track.edges.append(a.edge)
		"add_scenery":
			_sim().remove_scenery(int(a.scenery.id))
			return
		"remove_scenery":
			_sim().add_scenery(a.scenery)
			return
	_sim().track_changed()

# ---------- run / persistence ----------

func _any_running() -> bool:
	for c in _sim().consists:
		if c.target_speed > 0.01 or absf(c.velocity) > 0.05:
			return true
	return false

func _toggle_run() -> void:
	var run := not _any_running()
	for c in _sim().consists:
		c.autopilot = true
		c.target_speed = 8.0 if run else 0.0
	_update_status()

func _save() -> void:
	if Serializer.save_to_file(_sim(), SAVE_PATH) == OK:
		print("Saved ", SAVE_PATH)

func _load() -> void:
	var w := Serializer.load_from_file(SAVE_PATH)
	if w != null:
		GameState.world = w
		_undo.clear()
		_redo.clear()
		_update_status()
		print("Loaded ", SAVE_PATH)

# ---------- top-down model sprites ----------

## Cached top-view render for a model, requesting it on first use.
func _sprite_for(model_id: StringName) -> Dictionary:
	if model_id == &"" or thumbs == null:
		return {}
	if _sprites.has(model_id):
		return _sprites[model_id]
	if not _sprites_requested.has(model_id):
		var def := _lib().get_def(model_id)
		if def == null or def.mesh_path == "":
			_sprites_requested[model_id] = true   # nothing to render, use box
			return {}
		_sprites_requested[model_id] = true
		thumbs.request_top_view(def, func(result: Variant) -> void:
			if typeof(result) == TYPE_DICTIONARY and is_instance_valid(self):
				_sprites[model_id] = result
				queue_redraw())
	return {}

# ---------- rendering ----------

func _process(_dt: float) -> void:
	if not _sim().consists.is_empty():
		queue_redraw()
		_update_status()   # Run/Stop button tracks trains coasting to a halt

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _view_size()), AppTheme.CANVAS_BG, true)
	_draw_terrain()
	_draw_scenery()
	_draw_grid()

	for e in _sim().track.edges:
		_draw_edge_track(e, 1.0, Color.WHITE)
	for ep in _sim().track.open_endpoints():
		var p := _to_screen(ep.pose.origin)
		draw_arc(p, 6.0, 0.0, TAU, 20, AppTheme.ENDPOINT, 2.0, true)
		draw_circle(p, 2.0, AppTheme.ENDPOINT)
	_draw_signals()
	_draw_ghost()

	for c in _sim().consists:
		for pl in c.car_placements():
			_draw_car(pl)

func _draw_ghost() -> void:
	var kind: String = "piece" if _drag_piece >= 0 else String(_tool.get("kind", ""))
	match kind:
		"piece":
			var cur := _current_piece()
			if cur < 0:
				return
			var sp := _snapped_pose(_mouse_world)
			var ghost := _edge_for(cur, sp.pose)
			if ghost != null:
				var tint: Color = AppTheme.GHOST_SNAP if sp.snapped else AppTheme.GHOST_FREE
				_draw_edge_track(ghost, tint.a, tint)
		"vehicle":
			_draw_vehicle_ghost()
		"scenery":
			var def := _lib().get_def(StringName(String(_tool.get("id", ""))))
			if def != null:
				_draw_scenery_model(_mouse_world, _ghost_rot, def, Color(0.5, 1.0, 0.6, 0.65))
		"signal":
			var node := _sim().blocks().nearest_node(_mouse_world, 2.5)
			if not node.is_empty():
				draw_arc(_to_screen(node.pos), 9.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3, 0.9), 2.0, true)
		"paint":
			var r := TerrainCatalog.cell_rect(TerrainCatalog.cell_of(_mouse_world))
			var t := TerrainCatalog.get_type(String(_tool.type))
			var col: Color = t.get("color", Color(1, 1, 1)) if not t.is_empty() else Color(0.9, 0.4, 0.4)
			col.a = 0.45
			var rect := Rect2(_to_screen(r.position), r.size * _ppm())
			draw_rect(rect, col, true)
			draw_rect(rect, Color(1, 1, 1, 0.5), false, 1.5)

func _draw_vehicle_ghost() -> void:
	var def := _lib().get_def(StringName(String(_tool.get("id", ""))))
	if def == null:
		return
	# Near a train's end: preview the car snapped into its coupled position.
	var tgt := TrainBuilder.couple_target(_sim(), def.length_m, _mouse_world)
	if not tgt.is_empty():
		var c: Consist = tgt.consist
		var pose := c.path.pose_at_distance(
			TrainBuilder.coupled_center_distance(c, String(tgt.end), def.length_m))
		var chalf := Vector2.RIGHT.rotated(pose.get_rotation()) * def.length_m * 0.5
		_draw_car({"front": pose.origin + chalf, "back": pose.origin - chalf,
			"kind": "engine" if def.category == "engine" else "car",
			"model_id": def.id, "health": 100.0}, Color(0.45, 0.8, 1.0, 0.8))
		var coupler: Vector2 = c.coupler_points()[tgt.end]
		draw_arc(_to_screen(coupler), 7.0, 0.0, TAU, 20, Color(0.45, 0.8, 1.0), 2.5, true)
		return
	var hit := TrainBuilder.nearest_track_point(_sim().track, _mouse_world)
	if hit.is_empty() or float(hit.dist) > TrainBuilder.PLACE_RANGE:
		draw_arc(_to_screen(_mouse_world), 8.0, 0.0, TAU, 20, Color(1.0, 0.35, 0.3, 0.8), 2.0, true)
		return
	var pose: Transform2D = hit.pose
	var ang := pose.get_rotation() + (PI if _ghost_mirror else 0.0)
	var half := Vector2.RIGHT.rotated(ang) * def.length_m * 0.5
	var pl := {"front": pose.origin + half, "back": pose.origin - half,
		"kind": "engine" if def.category == "engine" else "car",
		"model_id": def.id, "health": 100.0}
	_draw_car(pl, Color(0.5, 1.0, 0.6, 0.65))

## Placed scenery models, under the track so rails stay readable across them.
func _draw_scenery() -> void:
	for s in _sim().scenery:
		var def := _lib().get_def(StringName(String(s.model_id)))
		if def != null:
			_draw_scenery_model(s.pos, float(s.rot), def)

## One scenery model seen from above: its real top-down render when available, a
## footprint circle until that render arrives (they are requested lazily).
func _draw_scenery_model(pos: Vector2, rot: float, def: ModelDef, tint: Color = Color.WHITE) -> void:
	var center := _to_screen(pos)
	var sprite := _sprite_for(def.id)
	if not sprite.is_empty():
		var half := float(sprite.span_m) * _ppm() * 0.5
		draw_set_transform(center, rot, Vector2.ONE)
		draw_texture_rect(sprite.texture, Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var r := def.length_m * 0.5 * _ppm()
	var col := Color(0.42, 0.47, 0.44, 0.55) if tint == Color.WHITE else tint
	draw_circle(center, r, col)
	draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.5, true)

## Painted terrain squares under everything else. Simple glyphs hint at the
## tall types (mountain/rocks/forest) that get real height in 3D.
func _draw_terrain() -> void:
	if _sim().terrain.is_empty():
		return
	var view := Rect2(_to_world(Vector2.ZERO), _view_size() / _ppm())
	for cell in _sim().terrain:
		var r := TerrainCatalog.cell_rect(cell)
		if not view.intersects(r):
			continue
		var t := TerrainCatalog.get_type(String(_sim().terrain[cell]))
		if t.is_empty():
			continue
		var rect := Rect2(_to_screen(r.position), r.size * _ppm())
		draw_rect(rect, t.color, true)
		var c := rect.get_center()
		var e := rect.size.x
		match String(t.id):
			"mountain", "rock":
				var peak_col: Color = (t.color as Color).darkened(0.25)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.28 * e, 0.22 * e), c + Vector2(0.0, -0.3 * e),
					c + Vector2(0.28 * e, 0.22 * e)]), peak_col)
			"forest":
				var tree_col: Color = (t.color as Color).darkened(0.3)
				draw_circle(c + Vector2(-0.15 * e, 0.05 * e), 0.11 * e, tree_col)
				draw_circle(c + Vector2(0.14 * e, -0.1 * e), 0.13 * e, tree_col)

const SIGNAL_COLORS := {
	"red": Color(1.0, 0.25, 0.2),
	"yellow": Color(1.0, 0.82, 0.25),
	"green": Color(0.3, 1.0, 0.45),
}

func _draw_signals() -> void:
	for s in _sim().signal_states():
		var p := _to_screen(s.pos)
		draw_circle(p, 6.5, Color(0.12, 0.13, 0.16))
		draw_circle(p, 4.5, SIGNAL_COLORS.get(String(s.state), Color.WHITE))
		draw_arc(p, 6.5, 0.0, TAU, 20, Color(0.75, 0.78, 0.85), 1.5, true)

## Meter grid anchored to the world, fading out as you zoom away.
func _draw_grid() -> void:
	var alpha := clampf((_ppm() - 6.0) / 40.0, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var tl := _to_world(Vector2.ZERO)
	var br := _to_world(_view_size())
	var minor := AppTheme.GRID_MINOR
	var major := AppTheme.GRID_MAJOR
	minor.a *= alpha
	major.a *= alpha
	for x in range(int(floor(tl.x)), int(ceil(br.x)) + 1):
		var sx := _to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, _view_size().y), major if x % 5 == 0 else minor, 1.0)
	for y in range(int(floor(tl.y)), int(ceil(br.y)) + 1):
		var sy := _to_screen(Vector2(0, y)).y
		draw_line(Vector2(0, sy), Vector2(_view_size().x, sy), major if y % 5 == 0 else minor, 1.0)

## Draw an edge as real track: ties first, then the two rails at gauge offset.
func _draw_edge_track(e: TrackEdge, alpha: float, tint: Color) -> void:
	var n := maxi(6, int(ceil(e.length() / 0.4)))
	var left_pts := PackedVector2Array()
	var right_pts := PackedVector2Array()
	for i in range(n + 1):
		var p := e.pose_at(e.length() * float(i) / float(n))
		var fwd := Vector2.RIGHT.rotated(p.get_rotation())
		var right := Vector2(-fwd.y, fwd.x)
		left_pts.append(_to_screen(p.origin - right * RAIL_OFFSET_M))
		right_pts.append(_to_screen(p.origin + right * RAIL_OFFSET_M))

	var tie_col := AppTheme.TIE if tint == Color.WHITE else tint
	tie_col.a = 0.9 * alpha if tint == Color.WHITE else tint.a * 0.6
	var tie_w := clampf(0.18 * _ppm(), 1.0, 5.0)
	var n_ties := maxi(1, int(e.length() / TIE_SPACING_M))
	for t in range(n_ties):
		var s := (float(t) + 0.5) * e.length() / float(n_ties)
		var p := e.pose_at(s)
		var fwd := Vector2.RIGHT.rotated(p.get_rotation())
		var right := Vector2(-fwd.y, fwd.x)
		draw_line(_to_screen(p.origin - right * TIE_HALF_M),
			_to_screen(p.origin + right * TIE_HALF_M), tie_col, tie_w)

	var rail_col := AppTheme.RAIL if tint == Color.WHITE else tint
	rail_col.a = alpha if tint == Color.WHITE else tint.a
	var rail_w := clampf(0.10 * _ppm(), 1.2, 4.0)
	draw_polyline(left_pts, rail_col, rail_w, true)
	draw_polyline(right_pts, rail_col, rail_w, true)

## One car: its real model's top-down render when available, a colored box
## otherwise. Damaged cars get a health bar.
func _draw_car(pl: Dictionary, tint: Color = Color.WHITE) -> void:
	var f: Vector2 = _to_screen(pl.front)
	var b: Vector2 = _to_screen(pl.back)
	var axis := f - b
	if axis.length() < 0.001:
		return
	var mid := (f + b) * 0.5
	var ang := axis.angle()
	var sprite := _sprite_for(StringName(String(pl.get("model_id", ""))))
	if not sprite.is_empty():
		var half := float(sprite.span_m) * _ppm() * 0.5
		draw_set_transform(mid, ang, Vector2.ONE)
		draw_texture_rect(sprite.texture, Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var dir := axis.normalized()
		var perp := Vector2(-dir.y, dir.x)
		var hw := CAR_HALF_W * _ppm() * 0.56
		var body := Color(0.90, 0.42, 0.20) if pl.kind == "engine" else Color(0.30, 0.52, 0.85)
		if tint != Color.WHITE:
			body = tint
		var corners := PackedVector2Array([b + perp * hw, f + perp * hw, f - perp * hw, b - perp * hw])
		draw_colored_polygon(corners, body)
		var outline := corners
		outline.append(corners[0])
		draw_polyline(outline, Color(0, 0, 0, 0.55), 1.5)
	var health := float(pl.get("health", 100.0))
	if health < 99.5 and tint == Color.WHITE:
		var w := 30.0
		var top := mid + Vector2(-w * 0.5, -14.0)
		draw_rect(Rect2(top, Vector2(w, 4.0)), Color(0, 0, 0, 0.6), true)
		var frac := health / 100.0
		draw_rect(Rect2(top, Vector2(w * frac, 4.0)),
			Color(0.85, 0.25, 0.2).lerp(Color(0.35, 0.85, 0.3), frac), true)
