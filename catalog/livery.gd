class_name Livery
extends Resource
## A paint scheme applied to a ModelDef's paintable_regions.
##
## FUTURE-FACING: reserved for the paint shop. In ride mode (Phase 3+) each region
## name maps to a material slot whose albedo is overridden by region_colors, so a
## player-authored or purchased livery is pure data — no per-model code.

@export var id: StringName = &""
@export var display_name: String = ""

# region name (from ModelDef.paintable_regions) -> Color
@export var region_colors: Dictionary = {}

# Future: decals / logos as {region, texture_path, uv_rect, color}.
@export var decals: Array = []

# Store (future): 0 = owned/free.
@export var price: int = 0
