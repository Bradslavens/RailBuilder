class_name ModelLibrary
extends RefCounted
## The id -> ModelDef registry of everything placeable as rolling stock (and later
## buildings/props). Combines built-in primitive models with assets scanned from
## the project and user asset folders. Views resolve Car.model_id through this;
## an unknown id simply falls back to the primitive box rendering.

const ASSET_DIRS := ["res://Assets", "user://assets"]

var _defs: Dictionary = {}      # StringName -> ModelDef
var _order: Array[StringName] = []

## The standard library: box primitives plus whatever is in the asset folders.
static func build_default() -> ModelLibrary:
	var lib := ModelLibrary.new()
	lib.add_builtins()
	for desc in AssetScanner.scan(ASSET_DIRS):
		lib.register_descriptor(desc)
	return lib

## The always-available primitive models (rendered as boxes, mesh_path empty).
func add_builtins() -> void:
	register_descriptor({"id": "box_engine", "display_name": "Box Engine",
		"category": "engine", "length_m": 9.0, "mass_kg": 40000.0, "path": ""})
	register_descriptor({"id": "box_car", "display_name": "Box Car",
		"category": "car", "length_m": 8.0, "mass_kg": 20000.0, "path": ""})

## Turn a scanner descriptor into a registered ModelDef. Same id re-registers
## (so user:// assets can override res:// ones scanned earlier).
func register_descriptor(desc: Dictionary) -> ModelDef:
	var d := ModelDef.new()
	d.id = StringName(String(desc.get("id", "")))
	d.display_name = String(desc.get("display_name", String(d.id)))
	d.category = String(desc.get("category", "prop"))
	d.mesh_path = String(desc.get("path", ""))
	d.length_m = float(desc.get("length_m", 8.0))
	d.mass_kg = float(desc.get("mass_kg", 10000.0))
	d.coupler_offset_m = float(desc.get("coupler_offset_m", 0.5))
	d.forward_axis = String(desc.get("forward_axis", "-z"))
	d.y_offset = float(desc.get("y_offset", 0.0))
	d.price = int(desc.get("price", 0))
	if not _defs.has(d.id):
		_order.append(d.id)
	_defs[d.id] = d
	return d

func get_def(id: StringName) -> ModelDef:
	return _defs.get(id)

func defs() -> Array[ModelDef]:
	var out: Array[ModelDef] = []
	for id in _order:
		out.append(_defs[id])
	return out

func by_category(category: String) -> Array[ModelDef]:
	var out: Array[ModelDef] = []
	for d in defs():
		if d.category == category:
			out.append(d)
	return out

## The engine to spawn by default: a real modeled one when available, otherwise
## the box primitive.
func default_engine() -> ModelDef:
	var engines := by_category("engine")
	for d in engines:
		if d.mesh_path != "":
			return d
	return engines[0] if not engines.is_empty() else null
