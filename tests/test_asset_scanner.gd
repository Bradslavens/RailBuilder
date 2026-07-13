extends TestCase
## AssetScanner: finds model files in asset directories and merges optional
## sidecar JSON metadata into plain descriptor dictionaries.

const DIR := "user://test_scan"

func _setup() -> Array:
	DirAccess.make_dir_recursive_absolute(DIR)
	_write(DIR + "/Wagon.glb", "fake")
	_write(DIR + "/EngineA.glb", "fake")
	_write(DIR + "/EngineA.json", JSON.stringify({
		"id": "loco_a", "display_name": "Loco A", "category": "engine", "length_m": 12.5}))
	_write(DIR + "/notes.txt", "not a model")
	var out := AssetScanner.scan([DIR])
	_cleanup()
	return out

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _cleanup() -> void:
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(DIR)

func test_scan_finds_only_model_files_sorted() -> void:
	var out := _setup()
	assert_eq(out.size(), 2, "two glb files")
	assert_eq(String(out[0].get("id", "")), "loco_a", "EngineA sorts first")
	assert_eq(String(out[1].get("id", "")), "wagon", "wagon id from filename")

func test_sidecar_overrides_defaults() -> void:
	var out := _setup()
	var loco: Dictionary = out[0]
	assert_eq(String(loco.get("category", "")), "engine", "sidecar category")
	assert_eq(String(loco.get("display_name", "")), "Loco A", "sidecar name")
	assert_approx(float(loco.get("length_m", 0.0)), 12.5, "sidecar length")

func test_no_sidecar_gets_defaults() -> void:
	var out := _setup()
	var wagon: Dictionary = out[1]
	assert_eq(String(wagon.get("display_name", "")), "Wagon", "name from filename")
	assert_eq(String(wagon.get("category", "")), "prop", "default category")
	assert_approx(float(wagon.get("length_m", 0.0)), 8.0, "default length")
	assert_true(String(wagon.get("path", "")).ends_with("Wagon.glb"), "path kept")

func test_missing_directory_is_empty_not_error() -> void:
	assert_eq(AssetScanner.scan(["user://does_not_exist"]).size(), 0, "no crash on missing dir")

const RDIR := "user://test_scan_recursive"

func test_recursive_scan_with_folder_categories() -> void:
	DirAccess.make_dir_recursive_absolute(RDIR + "/Engines/Loco1")
	DirAccess.make_dir_recursive_absolute(RDIR + "/TrainCars")
	DirAccess.make_dir_recursive_absolute(RDIR + "/Tracks")
	_write(RDIR + "/Engines/Loco1/Loco1.glb", "fake")
	_write(RDIR + "/TrainCars/Boxcar.glb", "fake")
	_write(RDIR + "/Tracks/Track_Straight.glb", "fake")   # skipped: track pipeline
	var out := AssetScanner.scan([RDIR])
	_remove_recursive(RDIR)
	assert_eq(out.size(), 2, "models found in subfolders, Tracks skipped")
	var by_id := {}
	for desc in out:
		by_id[desc["id"]] = desc
	assert_true(by_id.has("loco1"), "engine found two levels deep")
	assert_eq(String(by_id["loco1"]["category"]), "engine", "category from Engines folder")
	assert_eq(String(by_id["boxcar"]["category"]), "car", "category from TrainCars folder")

func _remove_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for s in d.get_directories():
		_remove_recursive(path.path_join(s))
	DirAccess.remove_absolute(path)
