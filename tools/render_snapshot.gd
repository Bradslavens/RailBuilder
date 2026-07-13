extends SceneTree
## Headless snapshot renderer. Builds an oval loop, spawns the demo train, advances
## the real simulation, then rasterizes the actual track + car poses to a PNG using
## the CPU Image API (no GPU/display needed). Verification aid — not part of the game.
##
##   godot4 --headless --path . --script res://tools/render_snapshot.gd -- <out.png> <seconds>

const W := 960
const H := 620
const MARGIN := 50.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "/tmp/railbuilder_snapshot.png"
	var seconds: float = float(args[1]) if args.size() > 1 else 2.5

	var w := _oval_world()
	var c := w.consists[0]
	var steps := int(seconds * 60.0)
	for _i in range(steps):
		w.tick(1.0 / 60.0)

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.09, 0.10, 0.13))

	# Compute world bounds from sampled track, so the view auto-fits.
	var pts := _sample_track(w)
	var b := _bounds(pts)
	var scale: float = minf((W - 2.0 * MARGIN) / maxf(b.size.x, 0.001), (H - 2.0 * MARGIN) / maxf(b.size.y, 0.001))

	# Track bed.
	for p in pts:
		var q := _to_px(p, b, scale)
		_stamp(img, q.x, q.y, 5.0, Color(0.62, 0.64, 0.72))

	# Open endpoints (should be none on a closed loop).
	for ep in w.track.open_endpoints():
		var q := _to_px(ep.pose.origin, b, scale)
		_stamp(img, q.x, q.y, 5.0, Color(0.30, 1.0, 0.45))

	# Train cars.
	for pl in c.car_placements():
		var f := _to_px(pl.front, b, scale)
		var bk := _to_px(pl.back, b, scale)
		var col := Color(0.92, 0.44, 0.20) if pl.kind == "engine" else Color(0.32, 0.54, 0.86)
		_line(img, f, bk, Consist.HALF_WIDTH * scale, col)

	var err := img.save_png(out_path)
	print("saved %s (rc=%d), train distance=%.2f m, speed=%.2f m/s" % [out_path, err, c.distance, c.velocity])
	quit(0)

func _oval_world() -> World:
	var w := World.new()
	# Racetrack oval: two straights joined by two 180-degree turns.
	var s1 := StraightEdge.new(Transform2D(0.0, Vector2(0, 0)), 22.0)
	w.track.add_edge(s1)
	var t1 := ArcEdge.new(s1.end_pose(), 7.0, PI)
	w.track.add_edge(t1)
	var s2 := StraightEdge.new(t1.end_pose(), 22.0)
	w.track.add_edge(s2)
	var t2 := ArcEdge.new(s2.end_pose(), 7.0, PI)
	w.track.add_edge(t2)
	var path := PathBuilder.build_from(w.track, w.track.edges[0])
	var train := Consist.demo(path)
	train.target_speed = 8.0
	w.consists.append(train)
	return w

func _sample_track(w: World) -> Array:
	var pts := []
	for e in w.track.edges:
		var n := 48
		for i in range(n + 1):
			pts.append(e.pose_at(e.length() * float(i) / float(n)).origin)
	return pts

func _bounds(pts: Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)

func _to_px(wp: Vector2, b: Rect2, scale: float) -> Vector2:
	var x := (wp.x - b.position.x) * scale + MARGIN
	var y := H - ((wp.y - b.position.y) * scale + MARGIN)   # flip Y so up is up
	return Vector2(x, y)

func _stamp(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var r2 := r * r
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, col)

func _line(img: Image, p0: Vector2, p1: Vector2, r: float, col: Color) -> void:
	var d := p0.distance_to(p1)
	var n := int(maxf(d / maxf(r * 0.5, 1.0), 1.0))
	for i in range(n + 1):
		var p := p0.lerp(p1, float(i) / float(n))
		_stamp(img, p.x, p.y, r, col)
