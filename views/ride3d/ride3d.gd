extends Node3D
## Phase 3 ride mode: a 3D view of the same GameState.world you build in 2D.
##
## Builds terrain + procedural track mesh once, then each frame drives box-car meshes
## and the cab camera from the sim's car_placements(). Read-only over the sim.
##
## Controls:
##   C     cycle cameras (Aerial / Free-fly / Cab)
##   Tab   back to 2D build mode
##   Free-fly cam: hold Right-Mouse to look, WASD move, Q/E down/up
##   Esc   release mouse

const FREE_SPEED := 14.0
const RAIL_TOP_Y := 0.16     # wheel height for grounded GLB models
const BOX_CAR_Y := 0.9       # center height for the fallback box bodies
const GROUND_SPAN := 900.0   # ground quad size; it follows the camera (infinite map)
const SCENERY_LOD_M := 260.0 # painted terrain stops rendering past this distance

var _cams: Array[Camera3D] = []
var _cam_idx := 0
var _car_nodes: Array[Node3D] = []
var _car_y: Array[float] = []
var _library: ModelLibrary
var _center := Vector3.ZERO

func _world() -> World:
	return GameState.world

func _ready() -> void:
	_setup_environment()
	_build_terrain()
	_build_painted_terrain()
	_build_scenery()
	_build_track()
	_build_cars()
	_build_signals()
	_setup_cameras()

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.50, 0.80)
	sky_mat.sky_horizon_color = Color(0.74, 0.80, 0.88)
	sky_mat.ground_bottom_color = Color(0.22, 0.26, 0.22)
	sky_mat.ground_horizon_color = Color(0.66, 0.71, 0.72)
	sky_mat.sun_angle_max = 30.0
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	# Strong enough that the view fades out toward the horizon (the "edge" of
	# the infinite map), gentle enough that the layout itself stays crisp.
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	($Env as WorldEnvironment).environment = env
	var sun := $Sun as DirectionalLight3D
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	_style_hud()

func _style_hud() -> void:
	var l := $HUD/Label as Label
	l.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_font_size_override("font_size", 13)

## The ground is a flat-colored plane that quietly re-centers under the active
## camera every frame (_follow_ground), so the world feels infinite while only
## ever rendering one quad. Distance fog hides its edge.
func _build_terrain() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_SPAN, GROUND_SPAN)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.34, 0.19)
	mat.roughness = 1.0
	var t := $Terrain as MeshInstance3D
	t.mesh = pm
	t.material_override = mat
	t.position = Vector3(0, -0.01, 0)

func _follow_ground() -> void:
	if _cams.is_empty():
		return
	var cam_pos := _cams[_cam_idx].global_position
	var t := $Terrain as MeshInstance3D
	t.position.x = cam_pos.x
	t.position.z = cam_pos.z

func _build_track() -> void:
	_center = _track_center()
	if _world().track.edges.is_empty():
		return
	# Edges with a matching GLB model get the real track asset; anything the model
	# set can't represent falls back to the procedural extruded mesh.
	var leftover: Array = []
	for e in _world().track.edges:
		var node := TrackAssets.build_edge_node(e)
		if node != null:
			$TrackHolder.add_child(node)
		else:
			leftover.append(e)
	if leftover.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = TrackMeshBuilder.build_mesh(leftover)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mi.material_override = mat
	$TrackHolder.add_child(mi)

func _track_center() -> Vector3:
	var edges := _world().track.edges
	if edges.is_empty():
		return Vector3.ZERO
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for e in edges:
		mn = mn.min(e.start_pose().origin).min(e.end_pose().origin)
		mx = mx.max(e.start_pose().origin).max(e.end_pose().origin)
	var c := (mn + mx) * 0.5
	return Vector3(c.x, 0, c.y)

## Painted terrain cells: flat colored tiles for ground types, cones for the
## tall ones (mountains, rocks, forest). Same data the 2D editor paints.
## Each cell fades out past SCENERY_LOD_M (simple LOD: distant cells cost
## nothing) — the fog has long since swallowed them anyway.
func _build_painted_terrain() -> void:
	var holder := Node3D.new()
	holder.name = "PaintedTerrain"
	add_child(holder)
	for cell in _world().terrain:
		var t := TerrainCatalog.get_type(String(_world().terrain[cell]))
		if t.is_empty():
			continue
		var r := TerrainCatalog.cell_rect(cell)
		var center := Geo3D.lift(r.get_center(), 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = t.color
		mat.roughness = 1.0
		var mi := MeshInstance3D.new()
		var h := float(t.height)
		if h > 0.05:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = TerrainCatalog.CELL_SIZE * (0.5 if String(t.id) == "forest" else 0.75)
			cone.height = h
			mi.mesh = cone
			mi.position = center + Vector3(0, h * 0.5, 0)
		else:
			var pm := PlaneMesh.new()
			pm.size = Vector2(TerrainCatalog.CELL_SIZE, TerrainCatalog.CELL_SIZE)
			mi.mesh = pm
			mi.position = center + Vector3(0, 0.02 + h, 0)
			if String(t.id) == "water":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.85
				mat.roughness = 0.2
		mi.material_override = mat
		mi.visibility_range_end = SCENERY_LOD_M
		mi.visibility_range_end_margin = 40.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mi)

# ---------- scenery ----------

## Placed scenery models (mountains, props). ModelLoader grounds each one at y = 0,
## so the pose from the 2D map is all that is needed. Deliberately not given the
## SCENERY_LOD_M range that painted cells get: a range is over a hundred meters
## across and would pop out while still filling the screen.
func _build_scenery() -> void:
	if _library == null:
		_library = ModelLibrary.build_default()
	var holder := Node3D.new()
	holder.name = "Scenery"
	add_child(holder)
	for s in _world().scenery:
		var node := ModelLoader.load_model(_library.get_def(StringName(String(s.model_id))))
		if node == null:
			continue
		node.transform = Geo3D.pose_transform(Transform2D(float(s.rot), s.pos as Vector2))
		holder.add_child(node)

# ---------- signals ----------

var _signal_lights: Dictionary = {}   # signal id -> StandardMaterial3D

func _build_signals() -> void:
	_signal_lights.clear()
	var bm := _world().blocks()
	for s in _world().signals:
		var node := bm.node_of_signal(s)
		var edge := _world().track.get_edge(int(s.edge_id))
		if node.is_empty() or edge == null:
			continue
		# Plant the post beside the track, using the anchoring endpoint's heading.
		var pose: Transform2D = edge.start_pose() if String(s.end) == "start" else edge.end_pose()
		var right := Vector2(-sin(pose.get_rotation()), cos(pose.get_rotation()))
		var base := Geo3D.lift((node.pos as Vector2) + right * 1.4, 0.0)
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = 1.6
		post.mesh = cyl
		var post_mat := StandardMaterial3D.new()
		post_mat.albedo_color = Color(0.35, 0.36, 0.4)
		post.material_override = post_mat
		post.position = base + Vector3(0, 0.8, 0)
		add_child(post)
		var lamp := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.16
		ball.height = 0.32
		lamp.mesh = ball
		var lamp_mat := StandardMaterial3D.new()
		lamp_mat.emission_enabled = true
		lamp.material_override = lamp_mat
		lamp.position = base + Vector3(0, 1.7, 0)
		add_child(lamp)
		_signal_lights[int(s.id)] = lamp_mat

const SIGNAL_COLORS := {
	"red": Color(1.0, 0.22, 0.18),
	"yellow": Color(1.0, 0.8, 0.2),
	"green": Color(0.25, 1.0, 0.4),
}

func _update_signals() -> void:
	if _signal_lights.is_empty():
		return
	for st in _world().signal_states():
		var mat: StandardMaterial3D = _signal_lights.get(int(st.id))
		if mat == null:
			continue
		var col: Color = SIGNAL_COLORS.get(String(st.state), Color.WHITE)
		mat.albedo_color = col
		mat.emission = col
		mat.emission_energy_multiplier = 1.6

# ---------- trains ----------

func _total_cars() -> int:
	var n := 0
	for c in _world().consists:
		n += c.cars.size()
	return n

func _build_cars() -> void:
	for n in _car_nodes:
		n.queue_free()
	_car_nodes.clear()
	_car_y.clear()
	if _library == null:
		_library = ModelLibrary.build_default()
	for consist in _world().consists:
		for car in consist.cars:
			# Cars with a modeled ModelDef get their GLB; everything else stays a box.
			var node: Node3D = ModelLoader.load_model(_library.get_def(car.model_id))
			if node != null:
				_car_y.append(RAIL_TOP_Y)
			else:
				node = _make_box_car(car)
				_car_y.append(BOX_CAR_Y)
			$Trains.add_child(node)
			_car_nodes.append(node)

func _make_box_car(car: Car) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 1.4, maxf(car.length_m * 0.9, 1.0))
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.44, 0.20) if car.kind == "engine" else Color(0.32, 0.54, 0.86)
	mat.roughness = 0.6
	mi.material_override = mat
	return mi

func _setup_cameras() -> void:
	# Frame the aerial camera to the layout's actual extent.
	var span := 30.0
	var edges := _world().track.edges
	if not edges.is_empty():
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for e in edges:
			mn = mn.min(e.start_pose().origin).min(e.end_pose().origin)
			mx = mx.max(e.start_pose().origin).max(e.end_pose().origin)
		span = maxf(30.0, (mx - mn).length() * 1.3)
	var aerial := $AerialCam as Camera3D
	aerial.transform = Transform3D(Basis(), _center + Vector3(0, span * 0.6, -span * 0.55)).looking_at(_center, Vector3.UP)
	($FreeCam as Camera3D).transform = aerial.transform
	_cams = [$AerialCam, $FreeCam, $CabCam]
	_cam_idx = 0
	_activate_cam()

func _activate_cam() -> void:
	for i in range(_cams.size()):
		_cams[i].current = (i == _cam_idx)

func _process(dt: float) -> void:
	if _total_cars() != _car_nodes.size():
		_build_cars()   # trains were edited (coupled/split) since last frame
	_update_cars()
	_update_signals()
	_update_cab()
	_follow_ground()
	if not _cams.is_empty() and _cams[_cam_idx] == $FreeCam:
		_update_free_cam(dt)

func _update_cars() -> void:
	var i := 0
	for consist in _world().consists:
		for pl in consist.car_placements():
			if i >= _car_nodes.size():
				return
			_car_nodes[i].transform = Geo3D.car_transform(pl.front, pl.back, _car_y[i])
			i += 1

func _update_cab() -> void:
	if _world().consists.is_empty():
		return
	var pls := _world().consists[0].car_placements()
	if pls.is_empty():
		return
	var fp := Geo3D.lift(pls[0].front, 1.9)
	var bp := Geo3D.lift(pls[0].back, 1.9)
	var fwd := fp - bp
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var pos := fp - fwd * 0.3
	($CabCam as Camera3D).transform = Transform3D(Basis(), pos).looking_at(pos + fwd, Vector3.UP)

func _update_free_cam(dt: float) -> void:
	var cam := $FreeCam as Camera3D
	var b := cam.global_transform.basis
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= b.z
	if Input.is_key_pressed(KEY_S): dir += b.z
	if Input.is_key_pressed(KEY_A): dir -= b.x
	if Input.is_key_pressed(KEY_D): dir += b.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir.length() > 0.0:
		cam.position += dir.normalized() * FREE_SPEED * dt

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_cam_idx = (_cam_idx + 1) % _cams.size()
				_activate_cam()
			KEY_TAB:
				get_tree().change_scene_to_file.call_deferred("res://views/build2d/build2d.tscn")
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var cam := $FreeCam as Camera3D
		cam.rotation.y -= event.relative.x * 0.005
		cam.rotation.x = clampf(cam.rotation.x - event.relative.y * 0.005, -1.4, 1.4)
