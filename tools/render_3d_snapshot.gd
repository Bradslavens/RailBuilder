extends SceneTree
## Headless software 3D renderer for verification. Builds an oval world + train, ticks
## the real sim, then rasterizes the real track mesh (TrackMeshBuilder) and box cars
## (Geo3D.car_transform) through a hand-rolled perspective rasterizer with a z-buffer.
## No GPU/display required. Not part of the game.
##
##   godot4 --headless --path . --script res://tools/render_3d_snapshot.gd -- <out.png> <seconds>

const W := 1000
const H := 620
const NEAR := 0.15
const LIGHT := Vector3(-0.4, -1.0, -0.35)

var _zbuf: PackedFloat32Array
var _img: Image
var _view: Transform3D
var _proj: Projection

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "/tmp/railbuilder_3d.png"
	var seconds: float = float(args[1]) if args.size() > 1 else 6.0

	var w := _oval_world()
	var c := w.consists[0]
	for _i in range(int(seconds * 60.0)):
		w.tick(1.0 / 60.0)

	_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.53, 0.71, 0.92))   # sky
	_zbuf = PackedFloat32Array()
	_zbuf.resize(W * H)
	_zbuf.fill(1.0e20)

	# Camera: 3/4 aerial looking at the loop center.
	var center := _center(w)
	var eye := center + Vector3(4, 30, -26)
	_view = Transform3D(Basis(), eye).looking_at(center + Vector3(0, 0, 2), Vector3.UP).affine_inverse()
	_proj = Projection.create_perspective(50.0, float(W) / float(H), NEAR, 800.0)

	# Terrain.
	var g := Color(0.30, 0.45, 0.25)
	_tri(Vector3(-40, 0, -30), Vector3(80, 0, -30), Vector3(80, 0, 60), g)
	_tri(Vector3(-40, 0, -30), Vector3(80, 0, 60), Vector3(-40, 0, 60), g)

	# Track mesh (the real builder output).
	var a := TrackMeshBuilder.build_arrays(w.track.edges)
	var v: PackedVector3Array = a.vertices
	var idx: PackedInt32Array = a.indices
	var cols: PackedColorArray = a.colors
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		_tri(v[i0], v[i1], v[i2], cols[i0])

	# Cars.
	for pl in c.car_placements():
		var col := Color(0.92, 0.44, 0.20) if pl.kind == "engine" else Color(0.32, 0.54, 0.86)
		var length: float = maxf(pl.front.distance_to(pl.back), 1.0)
		var xf := Geo3D.car_transform(pl.front, pl.back, 0.9)
		_box(xf, Vector3(2.4, 1.4, length), col)

	var err := _img.save_png(out_path)
	print("saved %s (rc=%d) speed=%.2f m/s dist=%.1f m tris_track=%d" % [out_path, err, c.velocity, c.distance, idx.size() / 3])
	quit(0)

func _oval_world() -> World:
	var w := World.new()
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
	train.target_speed = 9.0
	w.consists.append(train)
	return w

func _center(w: World) -> Vector3:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for e in w.track.edges:
		mn = mn.min(e.start_pose().origin).min(e.end_pose().origin)
		mx = mx.max(e.start_pose().origin).max(e.end_pose().origin)
	var c := (mn + mx) * 0.5
	return Vector3(c.x, 0, c.y)

func _box(xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corner := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corner.append(xf * Vector3(sx * h.x, sy * h.y, sz * h.z))
	# 6 faces (as index quads into the 8 corners) -> 12 triangles.
	var faces := [
		[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1],
		[2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3],
	]
	for f in faces:
		_tri(corner[f[0]], corner[f[1]], corner[f[2]], col)
		_tri(corner[f[0]], corner[f[2]], corner[f[3]], col)

## Rasterize one world-space triangle with flat shading + z-buffer.
func _tri(w0: Vector3, w1: Vector3, w2: Vector3, base: Color) -> void:
	var n := (w1 - w0).cross(w2 - w0)
	if n.length() < 1e-9:
		return
	n = n.normalized()
	var shade := 0.35 + 0.65 * absf(n.dot(LIGHT.normalized()))
	var col := Color(base.r * shade, base.g * shade, base.b * shade)

	var p0 = _project(w0)
	var p1 = _project(w1)
	var p2 = _project(w2)
	if p0 == null or p1 == null or p2 == null:
		return
	var s0: Vector3 = p0
	var s1: Vector3 = p1
	var s2: Vector3 = p2

	var minx := int(clampf(floorf(minf(s0.x, minf(s1.x, s2.x))), 0, W - 1))
	var maxx := int(clampf(ceilf(maxf(s0.x, maxf(s1.x, s2.x))), 0, W - 1))
	var miny := int(clampf(floorf(minf(s0.y, minf(s1.y, s2.y))), 0, H - 1))
	var maxy := int(clampf(ceilf(maxf(s0.y, maxf(s1.y, s2.y))), 0, H - 1))
	var denom := (s1.y - s2.y) * (s0.x - s2.x) + (s2.x - s1.x) * (s0.y - s2.y)
	if absf(denom) < 1e-9:
		return
	for py in range(miny, maxy + 1):
		for px in range(minx, maxx + 1):
			var fx := float(px) + 0.5
			var fy := float(py) + 0.5
			var a := ((s1.y - s2.y) * (fx - s2.x) + (s2.x - s1.x) * (fy - s2.y)) / denom
			var b := ((s2.y - s0.y) * (fx - s2.x) + (s0.x - s2.x) * (fy - s2.y)) / denom
			var cc := 1.0 - a - b
			if a < 0.0 or b < 0.0 or cc < 0.0:
				continue
			var depth := a * s0.z + b * s1.z + cc * s2.z
			var zi := py * W + px
			if depth < _zbuf[zi]:
				_zbuf[zi] = depth
				_img.set_pixel(px, py, col)

## World point -> screen Vector3(x, y, ndc_depth), or null if behind the near plane.
func _project(wp: Vector3):
	var vp := _view * wp
	if vp.z > -NEAR:
		return null
	var clip := _proj * Vector4(vp.x, vp.y, vp.z, 1.0)
	if clip.w <= 0.0:
		return null
	var ndc := Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
	return Vector3((ndc.x * 0.5 + 0.5) * W, (1.0 - (ndc.y * 0.5 + 0.5)) * H, ndc.z)
