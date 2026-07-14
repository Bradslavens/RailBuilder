---
name: blender-model
description: Author a new 3D model from scratch in Blender with a headless Python script and import it into RailBuilder (engine, car, track piece, building, prop, scenery). Use when the user wants a model built rather than downloaded — "make me a boxcar", "build a water tower", "model a station", "create a low-poly X" — or wants an existing tools/blender/*.py generator changed.
---

# Authoring a RailBuilder model in Blender

Models are built by **headless Python scripts committed to `tools/blender/`**, never by
hand in the GUI. The script is the source of truth: it can be re-run, tweaked, and
reviewed. Follow the existing ones — `build_steam_engine.py`, `build_passenger_car.py`
(from-scratch geometry), `import_terrain_model.py` (converting a download).

Blender: `~/Downloads/blender-5.1.2-linux-x64/blender`

```bash
~/Downloads/blender-5.1.2-linux-x64/blender --background --python tools/blender/build_thing.py -- <args>
```

## The asset contract

A script must guarantee all of this, or the model imports wrong:

- **Meters at real scale.** The steam engine is 9.35 m, a car 8.5-13 m, track cells 2 m.
- **Forward is Blender +Y**, which exports to Godot **-Z**. If you instead author the
  long axis along X, you must set `"forward_axis": "x"` in the sidecar.
- **Rests on the ground**: lowest vertex at Blender Z=0 → Godot Y=0. For rolling stock
  that means the wheels, not the chassis.
- **Origin centered** on the wheelbase (rolling stock) or on the footprint (scenery).
- **All transforms applied** (`bpy.ops.object.transform_apply(location, rotation, scale)`).
  Un-applied scale is the most common cause of a model importing at the wrong size.
- **Low poly** — see below. This is a hard requirement, not a preference.
- **A sidecar `<Name>.json`** written next to the GLB.

Export with `export_scene.gltf(export_format="GLB", export_yup=True, export_apply=True)`.

## Low poly is mandatory

RailBuilder is deliberately low-poly: a whole consist plus scenery can be on screen at
once. Build to a budget and state the triangle count you landed on.

| Kind | Target tris |
|---|---|
| Landscape / scenery | ~5,000 |
| Engine / rolling stock | ~3,000-8,000 |
| Small prop / building | ~1,000-3,000 |

Authoring from scratch, this mostly means *not* generating density in the first place:
low `segments` on cylinders (8-12 is plenty for a boiler, wheel or stack), no
subdivision surface, no bevel modifiers with high segment counts, and flat shading
unless a surface genuinely needs to read as smooth. Prefer flat-color Principled
materials over textures — it keeps the GLB tiny and matches the existing stock.

If a script does end up producing dense geometry, decimate before export:

```python
mod = obj.modifiers.new("Decimate", "DECIMATE")
mod.decimate_type = "COLLAPSE"
mod.ratio = target_tris / current_tris     # COLLAPSE preserves UVs
mod.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=mod.name)
```

Count triangles with `sum(len(p.vertices) - 2 for p in obj.data.polygons)` and print it,
so the budget is visible in the build output. `import_terrain_model.py` does exactly
this and is the reference implementation. If you use textures at all, keep them at
1024² or smaller.

## The sidecar

```json
{
  "id": "boxcar_oldwest",
  "display_name": "Old West Boxcar",
  "category": "car",
  "length_m": 8.5,
  "mass_kg": 20000,
  "forward_axis": "-z",
  "y_offset": 0.0,
  "price": 0
}
```

`category` is `engine` | `car` | `terrain` | `prop` (the `Assets/<Folder>/` name supplies
a default via `AssetScanner.FOLDER_CATEGORIES`; the sidecar wins).

**`length_m` is a scale factor, not a label.** `ModelLoader` rescales the model so its
depth along -Z equals `length_m`. For scenery with no real "forward", `length_m` must be
the model's own Z depth so the factor comes out at 1.0 — otherwise the meters you
carefully authored get stretched. (Blender is Z-up and glTF is Y-up, so Blender's **Y**
dimension is glTF's **Z**.)

## Track pieces are special

`Assets/Tracks/` has its own pipeline (`render/track_assets.gd`), skipped by the asset
scanner. Each piece has its Entry at the origin facing -Z and a `*_Exit` marker node.
Curves are radius 6 to match `PieceCatalog`; the straight tile is 2 m and gets tiled and
z-scaled to fill an edge. Sim `sweep > 0` (CCW in 2D) maps to the **"R"** models, because
lifting XZ mirrors handedness. Rail top sits at y ≈ 0.16.

## After the script runs

1. **Importer must be `keep`.** Godot writes `importer="scene"` for a new GLB, which
   drops the source from the exported pack — the game loads raw GLB bytes at runtime and
   `ModelLoader` returns null *silently*, so the model vanishes from exported builds while
   working in the editor. Run `godot --headless --import`, then rewrite the `.glb.import`
   to `importer="keep"` / `dest_files=[]`, and re-import to confirm. Delete any loose
   `<Name>_Image_*.jpg`/`png` the scene importer extracted; the GLB embeds its textures.
   `.import` files are tracked in git deliberately.

2. **Probe it**: `godot --headless --path . --script res://tools/asset_probe.gd` prints
   each model's load status and **normalized** size, and checks track GLBs for their
   `*_Exit` markers. The normalized size is where a wrong `length_m` or `forward_axis`
   shows up.

3. **Look at it.** Either shoot the real game —
   `RB_SHOT=$HOME/s.png RB_VIEW=ride3d RB_CAR=<id> godot --path . res://tools/ui_shot.tscn`
   (`RB_SCENERY=<id>`, `RB_ZOOM`, `RB_PAN` for the 2D map) — or render the GLB straight
   out of Blender with EEVEE next to a 9.35 m reference box for scale. Then Read the PNG.
   In Blender 5.1 the engine enum is `BLENDER_EEVEE`, not `BLENDER_EEVEE_NEXT`.

4. `./run_tests.sh`, grepping for `SCRIPT ERROR` as well as failures — the runner counts
   only assertion failures, so a script error aborts a test silently and still prints green.

New `class_name` files need `godot --headless --path . --import` before headless tests
can see them.
