class_name Car
extends RefCounted
## One vehicle in a consist. Phase 2 keeps this minimal (length + mass + kind);
## Phase 7 will back it with a ModelDef so cars become purchasable/paintable.

const MIN_HEALTH := 5.0         # cars get damaged but never die

var length_m: float = 8.0
var mass_kg: float = 20000.0
var kind: String = "car"        # "engine" or "car"
var model_id: StringName = &""  # ModelLibrary id for 3D visuals ("" = box fallback)
var health: float = 100.0       # collision damage; floors at MIN_HEALTH

func apply_damage(amount: float) -> void:
	health = maxf(health - amount, MIN_HEALTH)

func _init(p_length: float = 8.0, p_mass: float = 20000.0, p_kind: String = "car") -> void:
	length_m = p_length
	mass_kg = p_mass
	kind = p_kind
