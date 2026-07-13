class_name ThumbnailRenderer
extends SubViewport
## Renders library models to textures off-screen: 3/4-angle icons for the asset
## dock, and top-down orthographic sprites the 2D editor draws on the map (so
## you edit with the actual look of the models). One reusable viewport; requests
## queue up and complete one per rendered frame via callbacks.

const ICON_SIZE := 96
const TOP_SIZE := 128

var _camera: Camera3D
var _queue: Array = []      # {def: ModelDef, top: bool, cb: Callable}
var _working := false

func _ready() -> void:
	size = Vector2i(ICON_SIZE, ICON_SIZE)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)

## Queue a 3/4 dock icon. cb receives a Texture2D (or null on failure).
func request_icon(def: ModelDef, cb: Callable) -> void:
	_queue.append({"def": def, "top": false, "cb": cb})
	_pump()

## Queue a top-down map sprite. cb receives {texture, span_m} or null.
## span_m is the world size (meters) of the square the texture covers.
func request_top_view(def: ModelDef, cb: Callable) -> void:
	_queue.append({"def": def, "top": true, "cb": cb})
	_pump()

func _pump() -> void:
	if _working or _queue.is_empty():
		return
	_working = true
	var job: Dictionary = _queue.pop_front()
	var result: Variant = await _render(job.def, bool(job.top))
	_working = false
	(job.cb as Callable).call(result)
	_pump()

func _render(def: ModelDef, top: bool) -> Variant:
	var model := ModelLoader.load_model(def)
	if model == null:
		return null
	add_child(model)
	var aabb := ModelLoader.merged_aabb(model)
	var span := 0.0
	if top:
		size = Vector2i(TOP_SIZE, TOP_SIZE)
		span = _frame_top(aabb)
	else:
		size = Vector2i(ICON_SIZE, ICON_SIZE)
		_frame_three_quarter(aabb)
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := get_texture().get_image()
	model.queue_free()
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	if not top:
		return tex
	return {"texture": tex, "span_m": span}

## 3/4 perspective view framing the model's bounding sphere.
func _frame_three_quarter(aabb: AABB) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var center := aabb.get_center()
	var radius := maxf(aabb.size.length() * 0.5, 0.001)
	var dist := radius / tan(deg_to_rad(_camera.fov) * 0.5) * 1.15
	var dir := Vector3(1.0, 0.65, 1.0).normalized()
	_camera.position = center + dir * dist
	_camera.look_at(center)

## Straight-down orthographic view. Oriented so the model's forward (-Z after
## ModelLoader normalization) points toward +u in the texture — the 2D editor
## then just rotates the sprite by the car's heading. Returns the world span.
func _frame_top(aabb: AABB) -> float:
	var center := aabb.get_center()
	var span := maxf(aabb.size.x, aabb.size.z) * 1.04
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = span
	var basis := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	_camera.transform = Transform3D(basis, center + Vector3(0, aabb.size.y + 2.0, 0))
	return span
