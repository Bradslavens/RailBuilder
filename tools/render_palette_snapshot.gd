extends SceneTree
## Headless CPU snapshot of the new drag-and-drop palette feature:
##   left  = the palette grid (each cell = real PieceCatalog.preview_points output)
##   right = a sample layout chained from several piece types, with open endpoints
## Verifies the piece catalog + snapping geometry without a GPU.
##
##   godot4 --headless --path . --script res://tools/render_palette_snapshot.gd -- <out.png>

const W := 1040
const H := 620

var _img: Image

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "/tmp/railbuilder_palette.png"

	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.10, 0.11, 0.14))

	_draw_palette(Rect2(20, 20, 420, 580))
	_draw_sample(Rect2(470, 20, 550, 580))

	var err := _img.save_png(out_path)
	print("saved %s (rc=%d)" % [out_path, err])
	quit(0)

func _draw_palette(area: Rect2) -> void:
	_border(area, Color(0.30, 0.32, 0.40))
	var cols := 2
	var rows := int(ceil(PieceCatalog.PIECES.size() / float(cols)))
	var cw := area.size.x / cols
	var ch := area.size.y / rows
	for i in PieceCatalog.PIECES.size():
		var cx := area.position.x + (i % cols) * cw
		var cy := area.position.y + (i / cols) * ch
		var cell := Rect2(cx + 6, cy + 6, cw - 12, ch - 12)
		var selected := (i == 0)
		_fill(cell, Color(0.24, 0.34, 0.50) if selected else Color(0.16, 0.17, 0.22))
		_border(cell, Color(0.40, 0.42, 0.50))
		_draw_piece_preview(PieceCatalog.PIECES[i], cell)

func _draw_piece_preview(def: Dictionary, cell: Rect2) -> void:
	var pts := PieceCatalog.preview_points(def, 24)
	if pts.size() < 2:
		return
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var span := mx - mn
	var pad := 18.0
	var avail := cell.size - Vector2(pad * 2, pad * 2)
	var sc := minf(avail.x / maxf(span.x, 0.001), avail.y / maxf(span.y, 0.001))
	var center := (mn + mx) * 0.5
	var cc := cell.position + cell.size * 0.5
	var prev := Vector2.INF
	for p in pts:
		var q := (p - center) * sc
		var sp := Vector2(cc.x + q.x, cc.y - q.y)
		if prev != Vector2.INF:
			_line(prev, sp, 2.2, Color(0.90, 0.92, 0.98))
		prev = sp

func _draw_sample(area: Rect2) -> void:
	_border(area, Color(0.30, 0.32, 0.40))
	# Chain pieces nose-to-tail, showing a rotated start plus flipped (right) curves.
	var graph := TrackGraph.new()
	var o := Transform2D(deg_to_rad(25.0), Vector2.ZERO)   # rotated start (rotation demo)
	var seq := [
		["straight", false], ["curve90", false], ["straight", false],
		["curve90", true], ["curve45", true], ["straight", false],
		["curve30", false], ["curve90", false],
	]
	for step in seq:
		var def: Dictionary = _by_id(str(step[0])).duplicate()
		if bool(step[1]) and def.get("type", "") == "arc":
			def["deg"] = -float(def["deg"])
		var e := PieceCatalog.make_def(def, o)
		graph.add_edge(e)
		o = e.end_pose()

	# Fit the track into the sample area.
	var samples: Array[Vector2] = []
	for e in graph.edges:
		var n := 20
		for i in range(n + 1):
			samples.append(e.pose_at(e.length() * float(i) / float(n)).origin)
	var mn: Vector2 = samples[0]
	var mx: Vector2 = samples[0]
	for p in samples:
		mn = mn.min(p)
		mx = mx.max(p)
	var span := mx - mn
	var pad := 40.0
	var sc := minf((area.size.x - pad * 2) / maxf(span.x, 0.001), (area.size.y - pad * 2) / maxf(span.y, 0.001))
	var center := (mn + mx) * 0.5
	var ac := area.position + area.size * 0.5
	var to_px := func(w: Vector2) -> Vector2:
		var q := (w - center) * sc
		return Vector2(ac.x + q.x, ac.y - q.y)

	for e in graph.edges:
		var n := 24
		var prev := Vector2.INF
		for i in range(n + 1):
			var sp: Vector2 = to_px.call(e.pose_at(e.length() * float(i) / float(n)).origin)
			if prev != Vector2.INF:
				_line(prev, sp, 4.0, Color(0.85, 0.85, 0.92))
			prev = sp
	for ep in graph.open_endpoints():
		var q: Vector2 = to_px.call(ep.pose.origin)
		_stamp(q.x, q.y, 6.0, Color(0.30, 1.0, 0.45))

func _by_id(pid: String) -> Dictionary:
	for d in PieceCatalog.PIECES:
		if d.get("id", "") == pid:
			return d
	return PieceCatalog.PIECES[0]

# ---- tiny raster helpers ----

func _fill(r: Rect2, col: Color) -> void:
	for y in range(int(r.position.y), int(r.position.y + r.size.y)):
		for x in range(int(r.position.x), int(r.position.x + r.size.x)):
			if x >= 0 and y >= 0 and x < W and y < H:
				_img.set_pixel(x, y, col)

func _border(r: Rect2, col: Color) -> void:
	_line(r.position, r.position + Vector2(r.size.x, 0), 1.5, col)
	_line(r.position + Vector2(r.size.x, 0), r.position + r.size, 1.5, col)
	_line(r.position + r.size, r.position + Vector2(0, r.size.y), 1.5, col)
	_line(r.position + Vector2(0, r.size.y), r.position, 1.5, col)

func _stamp(cx: float, cy: float, rad: float, col: Color) -> void:
	var r2 := rad * rad
	for y in range(int(cy - rad), int(cy + rad) + 1):
		for x in range(int(cx - rad), int(cx + rad) + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				_img.set_pixel(x, y, col)

func _line(p0: Vector2, p1: Vector2, rad: float, col: Color) -> void:
	var d := p0.distance_to(p1)
	var n := int(maxf(d / maxf(rad * 0.5, 1.0), 1.0))
	for i in range(n + 1):
		var p := p0.lerp(p1, float(i) / float(n))
		_stamp(p.x, p.y, rad, col)
