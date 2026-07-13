class_name AssetDock
extends PanelContainer
## The asset browser: a filesystem-style tree docked beside the map (like the
## Godot editor's FileSystem panel). Folders open to reveal placeable items with
## little icons — drawn line previews for track pieces, rendered 3D thumbnails
## for models, swatches for terrain paint. Built to scale to hundreds of
## purchasable assets.
##
## Clicking an item selects it as the map's active tool ({kind: piece|vehicle|
## signal|paint, ...}); track pieces can also be dragged straight onto the map.

signal tool_selected(tool: Dictionary)

const PIECE_ICON := 26
const MODEL_ICON := 30

## Model category id -> folder label, in display order.
const CATEGORY_FOLDERS := [
	["engine", "Engines"],
	["car", "Train Cars"],
	["terrain", "Scenery Models"],
	["prop", "Props"],
]

var _tree: Tree
var _library: ModelLibrary
var _thumbs: ThumbnailRenderer
var _tool_items: Array = []          # {item: TreeItem, tool: Dictionary}
var _syncing := false                # guards item_selected while syncing from the map

func _ready() -> void:
	custom_minimum_size = Vector2(250, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var title := Label.new()
	title.text = "ASSETS"
	AppTheme.style_section_label(title)
	vb.add_child(title)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_SINGLE
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_item_selected)
	_tree.set_drag_forwarding(_get_tree_drag_data, Callable(), Callable())
	vb.add_child(_tree)

## Build the tree. thumbs is the shared off-screen renderer owned by the shell.
func setup(library: ModelLibrary, thumbs: ThumbnailRenderer) -> void:
	_library = library
	_thumbs = thumbs
	_tree.clear()
	_tool_items.clear()
	var root := _tree.create_item()
	_build_track_folder(root)
	for pair in CATEGORY_FOLDERS:
		_build_model_folder(root, pair[0], pair[1])
	_build_signal_folder(root)
	_build_paint_folder(root)

func _add_tool_item(folder: TreeItem, label: String, icon: Texture2D, tool: Dictionary, tip: String) -> TreeItem:
	var item := _tree.create_item(folder)
	item.set_text(0, label)
	if icon != null:
		item.set_icon(0, icon)
	item.set_icon_max_width(0, MODEL_ICON)
	item.set_tooltip_text(0, tip)
	item.set_metadata(0, tool)
	_tool_items.append({"item": item, "tool": tool})
	return item

func _build_track_folder(root: TreeItem) -> void:
	var folder := _make_folder(root, "Track")
	for i in PieceCatalog.PIECES.size():
		var d: Dictionary = PieceCatalog.PIECES[i]
		var item := _add_tool_item(folder, str(d.get("label", "?")), _piece_icon(d),
			{"kind": "piece", "index": i}, "Click to select, or drag onto the map")
		item.set_icon_max_width(0, PIECE_ICON)

func _build_model_folder(root: TreeItem, category: String, label: String) -> void:
	var defs := _library.by_category(category)
	if defs.is_empty():
		return
	var folder := _make_folder(root, label)
	folder.collapsed = category != "engine"
	for def in defs:
		var tip := "Click, then click on track to place it — drop it next to a\ntrain's end to couple. X removes the car under the cursor."
		var item := _add_tool_item(folder, def.display_name, _box_icon(category),
			{"kind": "vehicle", "id": String(def.id)}, tip)
		if def.mesh_path != "" and _thumbs != null:
			_thumbs.request_icon(def, func(tex: Variant) -> void:
				if tex is Texture2D and is_instance_valid(_tree):
					item.set_icon(0, tex))

func _build_signal_folder(root: TreeItem) -> void:
	var folder := _make_folder(root, "Signals")
	_add_tool_item(folder, "Block Signal", _signal_icon(), {"kind": "signal"},
		"Click a track joint to place/remove a signal. Signals split the\ntrack into blocks; trains won't enter an occupied block.")

func _build_paint_folder(root: TreeItem) -> void:
	var folder := _make_folder(root, "Terrain Paint")
	folder.collapsed = true
	for t in TerrainCatalog.TYPES:
		_add_tool_item(folder, str(t.label), _swatch_icon(t.color),
			{"kind": "paint", "type": String(t.id)}, "Click/drag on the map to paint")
	_add_tool_item(folder, "Erase", _erase_icon(), {"kind": "paint", "type": ""},
		"Click/drag to clear painted terrain")

func _make_folder(root: TreeItem, label: String) -> TreeItem:
	var folder := _tree.create_item(root)
	folder.set_text(0, label)
	folder.set_icon(0, get_theme_icon("folder", "FileDialog"))
	folder.set_icon_modulate(0, AppTheme.ACCENT)
	folder.set_selectable(0, false)
	folder.set_metadata(0, {"kind": "folder"})
	return folder

# ---------- selection ----------

func _on_item_selected() -> void:
	if _syncing:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY and meta.get("kind", "") != "folder":
		tool_selected.emit(meta)

## Keep the tree highlight in sync when the map changes the tool another way
## (number keys, right-click deselect, drop).
func show_tool_selected(tool: Dictionary) -> void:
	_syncing = true
	var found := false
	for entry in _tool_items:
		if entry.tool == tool:
			(entry.item as TreeItem).select(0)
			found = true
			break
	if not found:
		var sel := _tree.get_selected()
		if sel != null:
			sel.deselect(0)
	_syncing = false

# ---------- drag ----------

## Native drag out of the tree: track pieces carry the same payload the old
## palette buttons did, so the map's drop handling is unchanged.
func _get_tree_drag_data(_at_position: Vector2) -> Variant:
	var item := _tree.get_selected()
	if item == null:
		return null
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY or meta.get("kind", "") != "piece":
		return null
	var idx := int(meta["index"])
	var preview := TextureRect.new()
	preview.texture = item.get_icon(0)
	preview.modulate = Color(1, 1, 1, 0.85)
	_tree.set_drag_preview(preview)
	tool_selected.emit(meta)
	return {"type": "track_piece", "index": idx}

# ---------- icons ----------

## Rasterize a piece's preview polyline into a small icon image.
func _piece_icon(def: Dictionary) -> Texture2D:
	var s := PIECE_ICON
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var pts := PieceCatalog.preview_points(def, 24)
	if pts.size() >= 2:
		var mn := pts[0]
		var mx := pts[0]
		for p in pts:
			mn = mn.min(p)
			mx = mx.max(p)
		var span := mx - mn
		var pad := 5.0
		var sc := minf((s - pad * 2.0) / maxf(span.x, 0.001), (s - pad * 2.0) / maxf(span.y, 0.001))
		var center := (mn + mx) * 0.5
		var mapped := PackedVector2Array()
		for p in pts:
			var q := (p - center) * sc
			mapped.append(Vector2(s * 0.5 + q.x, s * 0.5 - q.y))
		for i in range(mapped.size() - 1):
			_plot_segment(img, mapped[i], mapped[i + 1], Color(0.90, 0.92, 0.98))
	return ImageTexture.create_from_image(img)

## Stamp 2x2 dots along a segment — crude anti-alias-free line, fine at icon size.
func _plot_segment(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := maxi(1, int(ceil(a.distance_to(b) * 2.0)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		for dx in range(2):
			for dy in range(2):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)

## Generic icon for the primitive box models (no mesh to thumbnail).
func _box_icon(category: String) -> Texture2D:
	var s := PIECE_ICON
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var col := Color(0.90, 0.42, 0.20) if category == "engine" else Color(0.30, 0.52, 0.85)
	img.fill_rect(Rect2i(3, s / 2 - 5, s - 6, 10), col)
	return ImageTexture.create_from_image(img)

## A tiny signal post with a green light.
func _signal_icon() -> Texture2D:
	var s := PIECE_ICON
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(s / 2 - 1, 6, 3, s - 10), Color(0.6, 0.6, 0.65))
	var c := Vector2(s / 2.0, 9.0)
	for x in range(s):
		for y in range(s):
			if Vector2(x, y).distance_to(c) <= 4.5:
				img.set_pixel(x, y, Color(0.30, 1.0, 0.45))
	return ImageTexture.create_from_image(img)

func _swatch_icon(col: Color) -> Texture2D:
	var s := PIECE_ICON
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(4, 4, s - 8, s - 8), col)
	return ImageTexture.create_from_image(img)

func _erase_icon() -> Texture2D:
	var s := PIECE_ICON
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for i in range(0, s - 8):
		for w in range(2):
			img.set_pixel(4 + i, 4 + i + w, Color(0.8, 0.4, 0.4))
			img.set_pixel(4 + i, s - 5 - i + w - 1, Color(0.8, 0.4, 0.4))
	return ImageTexture.create_from_image(img)
