class_name ModelDef
extends Resource
## Data-driven definition of a placeable model (engine, car, building, prop).
##
## FUTURE-FACING: rolling stock and structures are described as data so that a
## marketplace ("purchase models") and a paint shop ("paint models") become new
## data + UI over this same schema rather than a refactor. Phase 1 does not use
## these yet — the seams are reserved here intentionally.

@export var id: StringName = &""
@export var display_name: String = ""
@export_enum("engine", "car", "building", "prop") var category: String = "car"

# Visuals (Phase 3+): path to the 3D mesh/scene used in ride mode.
@export var mesh_path: String = ""

# Normalization hints for imported models (see ModelLoader): which model-space
# axis the vehicle's front faces, and a vertical fudge after grounding at y=0.
@export var forward_axis: String = "-z"
@export var y_offset: float = 0.0

# Physics (Phase 2+): used by the longitudinal train dynamics.
@export var length_m: float = 8.0
@export var mass_kg: float = 10000.0
@export var coupler_offset_m: float = 0.5

# Painting (future): named surfaces a Livery may recolor.
@export var paintable_regions: PackedStringArray = PackedStringArray()

# Store (future): 0 = owned/free. Non-zero gates behind a purchase.
@export var price: int = 0
