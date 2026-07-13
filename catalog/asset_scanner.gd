class_name AssetScanner
extends RefCounted
## Finds model files (.glb/.gltf) in asset directories and merges optional sidecar
## metadata into plain descriptor dictionaries for ModelLibrary to register.
##
## Scanning is recursive so assets can live in a folder hierarchy — e.g.
## Assets/Engines/SteamEngine1800s/SteamEngine1800s.glb — and the top-level folder
## a model sits under gives its default category (see FOLDER_CATEGORIES). The
## Assets/Tracks folder is skipped: it holds special-purpose track models with
## their own pipeline (see TrackAssets).
##
## A sidecar is a JSON file next to the model with the same basename
## (SteamEngine1800s.glb -> SteamEngine1800s.json). Recognized keys: id,
## display_name, category, length_m, mass_kg, coupler_offset_m, forward_axis,
## y_offset, price. Everything is defaulted so a bare drag-and-dropped GLB still
## scans (as a generic prop until it gets a sidecar or a category folder).

const MODEL_EXTENSIONS := ["glb", "gltf"]
const SKIP_DIRS := ["Tracks", "textures"]

## Top-level asset folder name -> default category for models under it.
const FOLDER_CATEGORIES := {
	"Engines": "engine",
	"TrainCars": "car",
	"Terrain": "terrain",
}

## Scan directories (in order, recursively) and return descriptor Dictionaries,
## sorted by name within each directory (files before subfolders). Missing
## directories are skipped silently.
static func scan(dirs: Array) -> Array:
	var out := []
	for dir_path in dirs:
		_scan_dir(String(dir_path), "", out)
	return out

static func _scan_dir(dir_path: String, category_hint: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	var files := Array(d.get_files())
	files.sort()
	for f in files:
		if String(f.get_extension()).to_lower() in MODEL_EXTENSIONS:
			out.append(_describe(dir_path.path_join(f), category_hint))
	var subdirs := Array(d.get_directories())
	subdirs.sort()
	for s in subdirs:
		if s in SKIP_DIRS or String(s).begins_with("."):
			continue
		var hint: String = category_hint
		if hint == "":
			hint = FOLDER_CATEGORIES.get(s, "")
		_scan_dir(dir_path.path_join(s), hint, out)

static func _describe(path: String, category_hint: String) -> Dictionary:
	var base := path.get_file().get_basename()
	var desc := {
		"path": path,
		"id": base.to_lower(),
		"display_name": base,
		"category": category_hint if category_hint != "" else "prop",
		"length_m": 8.0,
		"mass_kg": 10000.0,
		"coupler_offset_m": 0.5,
		"forward_axis": "-z",
		"y_offset": 0.0,
		"price": 0,
	}
	var sidecar_path := path.get_base_dir().path_join(base + ".json")
	if FileAccess.file_exists(sidecar_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in parsed:
				desc[k] = parsed[k]
	return desc
