---
name: import-meshy-model
description: Import a downloaded Meshy AI (or similar) GLB into RailBuilder as a usable low-poly asset — decimate, rescale to real meters, write the sidecar, fix the Godot importer, verify it loads. Use whenever the user points at a downloaded .glb/.gltf (typically in ~/Downloads, named Meshy_AI_*) and wants it in the game, or says "convert this to low poly", "import this model", "add this mountain/engine/car/building".
---

# Importing a downloaded Meshy model

Meshy downloads are never game-ready: ~200-250k triangles, 2048² textures, ~15-20 MB,
and authored at unit scale (bounding box ~1-2 units) rather than in meters. The job is
always the same four steps. **Do not hand-place a raw Meshy GLB into `Assets/`.**

## 0. Probe the source first

Never guess the mesh's size or topology — read it:

```bash
python3 -c "
import struct,json
f=open('SOURCE.glb','rb')
struct.unpack('<III',f.read(12)); clen,_=struct.unpack('<II',f.read(8))
j=json.loads(f.read(clen))
for m in j['meshes']:
    for p in m['primitives']:
        a=j['accessors'][p['attributes']['POSITION']]
        print('bbox', a['min'], a['max'])
        print('tris', j['accessors'][p['indices']]['count']//3)
print('images', [i.get('mimeType') for i in j.get('images',[])])
"
```

The bbox tells you which axis is longest and what to scale by. **This user's models
often have their long axis on X**, which matters for rolling stock (see step 2).

## 1. Convert with the Blender script

`tools/blender/import_terrain_model.py` does decimate + rescale + ground + texture
shrink + sidecar in one pass. Blender lives at
`~/Downloads/blender-5.1.2-linux-x64/blender`.

```bash
~/Downloads/blender-5.1.2-linux-x64/blender --background \
  --python tools/blender/import_terrain_model.py -- \
  --source ~/Downloads/Meshy_AI_whatever.glb \
  --name MountainRange_Snow --out-dir Assets/Terrain \
  --height 60 --tris 5000 --display-name "Snowy Mountain Range"
```

It writes `Assets/<Category>/<Name>/<Name>.glb` + `<Name>.json`.

Pick a real-world size deliberately and say what you picked. Reference points: the
steam engine is 9.35 m long, track cells are 2 m, painted "mountain" terrain is 7 m
tall. The snow range was scaled to 60 m tall / 143 m wide so it reads as a mountain
rather than a hill.

### Low poly is mandatory, not optional

**Never ship a Meshy mesh at its download density.** A raw 235k-tri model is roughly
50× the budget of everything else in the game, and RailBuilder can have many models on
screen at once (a whole consist plus scenery). Always decimate, even if the user does
not say "low poly" — and say what you took it from and to.

Budgets that have worked (`--tris`):

| Kind | Target | Why |
|---|---|---|
| Landscape / scenery | ~5,000 | Silhouette is all that matters at distance |
| Engine / rolling stock | ~3,000-8,000 | Seen close-up from the cab camera; keep more detail on the near silhouette |
| Small prop / building | ~1,000-3,000 | Placed in numbers |

The snow mountain went 235k → 4,999 tris with no visible loss at play distance:
silhouette, ridgelines and snow texturing all survived, and the file went from 15 MB
to 564 KB. Decimate COLLAPSE preserves the UVs, so the original textures still map —
which is why the Meshy texturing survives the cut.

Also shrink the textures: Meshy ships four 2048² maps (~8 MB). 1024² (`--texture-size`,
the default) is plenty and is most of the file-size win. Verify the result visually
(step 4) — decimation is the one step that can quietly wreck a model, and the tri count
alone will not tell you.

## 2. Get `length_m` right — this is the easy way to break it

`ModelLoader` **rescales every model so its depth along -Z equals the sidecar's
`length_m`**, then grounds it at y = 0. So `length_m` is not decoration, it is the
scale factor.

- **Scenery/props** (no meaningful "forward"): `length_m` must be the model's own
  **Z depth**, so the scale factor works out to exactly 1.0 and the meters you baked
  in Blender survive. Setting it to the width instead silently stretched the mountain
  from 143×60 m to 166×70 m. The import script derives this correctly (Blender is
  Z-up, so Blender's Y is glTF's Z).
- **Rolling stock**: set `forward_axis` to the axis the model actually faces
  (`"x"` if the long axis is X, as with `Boxcar_OldWest`) and `length_m` to its real
  length. Without this, a car normalizes to absurd dimensions.

## 3. Fix the Godot importer — silently breaks exported builds

Godot generates a `.glb.import` for any new GLB with `importer="scene"`, which
converts it to a `.scn` and **drops the source file from the exported pack**. The game
reads raw GLB bytes at runtime via `GLTFDocument.append_from_file`, and
`ModelLoader._load_gltf` returns null without an error — so the model just silently
does not exist in an exported build, while working fine in the editor.

Every `.glb.import` must read:

```ini
[remap]

importer="keep"
type=""
uid="uid://<keep whatever Godot generated>"

[deps]

source_file="res://Assets/.../Name.glb"
dest_files=[]

[params]

```

Run `godot --headless --import` first (it creates the file and assigns a uid), then
rewrite it to `keep`. Re-run `--import` afterwards to confirm it sticks. Switching to
`keep` also stops Godot extracting the embedded textures as loose files — delete any
`<Name>_Image_*.jpg` it made, the GLB carries its own.

`.import` files are tracked in git on purpose. Do not gitignore them.

## 4. Verify — never claim it works without this

```bash
godot --headless --path . --script res://tools/asset_probe.gd
```

It prints every scanned model, whether it loads, and its **normalized** size. Check the
size is what you intended: if `length_m` is wrong, this is where you see it. Then look
at it in the real game:

```bash
RB_SHOT=$HOME/shot.png RB_VIEW=ride3d RB_SCENERY=<id> \
  godot --path . res://tools/ui_shot.tscn
```

and Read the PNG. `RB_VIEW=build2d` with `RB_ZOOM` / `RB_PAN` frames the 2D map
(`RB_CAR=<id>` couples a specific car instead). Note the ride3d aerial camera frames
only the *track*, and is a steep downward view — a large model placed too far away
projects **above** the top of the frame and vanishes. Around 130 m out framed the
143 m mountain; 230 m put it off-screen.

Finally, run `./run_tests.sh` and grep for `SCRIPT ERROR` as well as failures — the
runner counts only assertion failures and a script error aborts a test silently while
still printing green.

## Where things go

`Assets/Engines/`, `Assets/TrainCars/`, `Assets/Terrain/` — the folder sets the default
category (`AssetScanner.FOLDER_CATEGORIES`); the sidecar JSON overrides it. Terrain and
prop models are placed as free-standing **scenery** (click anywhere, Q/E rotate, X to
remove); engines and cars are placed on track through `TrainBuilder`. Scenery has no
collision.
