class_name TerrainCatalog
extends RefCounted
## The palette of paintable terrain, data-driven like PieceCatalog. The world
## stores painted cells as Vector2i -> type id on a CELL_SIZE meter grid; both
## views render from the same data (flat color in 2D, colored tile with height
## in 3D). New terrain types are just new entries.

const CELL_SIZE := 2.0   # meters per painted square

## {id, label, color (both views), height (3D meters; 0 = flat, <0 = sunken)}
const TYPES := [
	{"id": "grass", "label": "Grass", "color": Color(0.30, 0.44, 0.22), "height": 0.0},
	{"id": "dirt", "label": "Dirt", "color": Color(0.42, 0.33, 0.22), "height": 0.0},
	{"id": "sand", "label": "Sand", "color": Color(0.72, 0.65, 0.44), "height": 0.0},
	{"id": "water", "label": "Water", "color": Color(0.18, 0.36, 0.58), "height": -0.25},
	{"id": "rock", "label": "Rocks", "color": Color(0.47, 0.46, 0.44), "height": 1.4},
	{"id": "mountain", "label": "Mountain", "color": Color(0.54, 0.51, 0.48), "height": 7.0},
	{"id": "forest", "label": "Forest", "color": Color(0.15, 0.30, 0.13), "height": 2.2},
	{"id": "snow", "label": "Snow", "color": Color(0.88, 0.90, 0.94), "height": 0.0},
]

static func get_type(id: String) -> Dictionary:
	for t in TYPES:
		if String(t.id) == id:
			return t
	return {}

## The grid cell containing world point p.
static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floorf(p.x / CELL_SIZE)), int(floorf(p.y / CELL_SIZE)))

## World-space rect of a cell.
static func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
