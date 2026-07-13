extends Control
## Root of the build view: an asset dock on the left and the map editor filling
## the rest, in a draggable split (like the Godot editor's FileSystem layout).
## Owns the shared ModelLibrary and the off-screen thumbnail renderer, and wires
## dock tool selection to the map (and back, so keyboard shortcuts keep the tree
## highlight in sync).

@onready var _dock: AssetDock = $HSplit/AssetDock
@onready var _map: Control = $HSplit/Map

func _ready() -> void:
	theme = AppTheme.build()
	var library := ModelLibrary.build_default()
	var thumbs := ThumbnailRenderer.new()
	add_child(thumbs)
	_map.library = library
	_map.thumbs = thumbs
	_dock.setup(library, thumbs)
	_dock.tool_selected.connect(_map.select_tool)
	_map.tool_changed.connect(_dock.show_tool_selected)
