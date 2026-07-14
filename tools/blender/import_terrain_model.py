"""Turn a high-poly downloaded GLB into a low-poly terrain/scenery asset.

Meshy-style downloads are ~200k tris with 2k textures, and are authored at unit
scale. This decimates the mesh, rescales it to a real-world height in meters,
drops its base to Y=0 (so it sits on the ground plane when placed), shrinks the
textures, and writes a GLB plus the JSON sidecar AssetScanner reads.

  blender --background --python tools/blender/import_terrain_model.py -- \
      --source ~/Downloads/mountain.glb --name MountainRange_Snow \
      --height 60 --tris 5000 --display-name "Snowy Mountain Range"
"""

import argparse
import json
import os
import sys

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True, help="high-poly .glb to convert")
    p.add_argument("--name", required=True, help="asset basename, e.g. MountainRange_Snow")
    p.add_argument("--out-dir", default="Assets/Terrain")
    p.add_argument("--height", type=float, default=60.0, help="target height in meters")
    p.add_argument("--tris", type=int, default=5000, help="target triangle count")
    p.add_argument("--texture-size", type=int, default=1024)
    p.add_argument("--display-name", default="")
    p.add_argument("--id", default="")
    return p.parse_args(argv)


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_and_join(source: str) -> bpy.types.Object:
    bpy.ops.import_scene.gltf(filepath=source)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"no mesh found in {source}")
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Bake the glTF Y-up correction (and any node scale) into the mesh data so
    # later dimension math is in the same space the exporter will write out.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def tri_count(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def decimate(obj: bpy.types.Object, target_tris: int) -> None:
    before = tri_count(obj)
    if before <= target_tris:
        print(f"[terrain] {before} tris already under target, skipping decimate")
        return
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = target_tris / before
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"[terrain] decimated {before} -> {tri_count(obj)} tris")


def rescale_and_ground(obj: bpy.types.Object, height_m: float) -> None:
    """Scale uniformly to height_m tall, then center on X/Z with the base at Y=0."""
    current = obj.dimensions.z  # Blender is Z-up; glTF export converts to Y-up.
    if current <= 0.0:
        raise SystemExit("model has no height")
    obj.scale = (height_m / current,) * 3
    bpy.ops.object.transform_apply(scale=True)

    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    min_x = min(c.x for c in corners)
    max_x = max(c.x for c in corners)
    min_y = min(c.y for c in corners)
    max_y = max(c.y for c in corners)
    min_z = min(c.z for c in corners)
    offset = (-(min_x + max_x) / 2.0, -(min_y + max_y) / 2.0, -min_z)
    for v in obj.data.vertices:
        v.co.x += offset[0]
        v.co.y += offset[1]
        v.co.z += offset[2]
    obj.location = (0.0, 0.0, 0.0)
    d = obj.dimensions
    print(f"[terrain] size {d.x:.1f} x {d.y:.1f} m footprint, {d.z:.1f} m tall")


def shrink_textures(max_size: int) -> None:
    for img in bpy.data.images:
        if img.size[0] <= max_size and img.size[1] <= max_size:
            continue
        w, h = img.size
        s = max_size / max(w, h)
        img.scale(max(1, int(w * s)), max(1, int(h * s)))
        print(f"[terrain] texture {img.name}: {w}x{h} -> {img.size[0]}x{img.size[1]}")


def main() -> None:
    args = parse_args()
    source = os.path.expanduser(args.source)
    out_dir = os.path.join(args.out_dir, args.name)
    os.makedirs(out_dir, exist_ok=True)

    clear_scene()
    obj = import_and_join(source)
    obj.name = args.name
    decimate(obj, args.tris)
    rescale_and_ground(obj, args.height)
    shrink_textures(args.texture_size)

    glb_path = os.path.join(out_dir, f"{args.name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        use_selection=False,
        export_image_format="JPEG",
    )

    # ModelLoader rescales every model so its depth along -Z equals length_m, so
    # length_m must be the model's own depth or the baked meters get stretched.
    # Blender is Z-up and the exporter writes Y-up, so Blender's Y is glTF's Z.
    d = obj.dimensions
    sidecar = {
        "id": args.id or args.name.lower(),
        "display_name": args.display_name or args.name,
        "category": "terrain",
        "length_m": round(d.y, 1),
        "mass_kg": 0,
        "forward_axis": "-z",
        "y_offset": 0.0,
        "price": 0,
    }
    with open(os.path.join(out_dir, f"{args.name}.json"), "w") as f:
        json.dump(sidecar, f, indent=2)
        f.write("\n")
    print(f"[terrain] wrote {glb_path}")


if __name__ == "__main__":
    main()
