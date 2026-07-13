"""Build a low-poly rustic 1800s steam engine (4-4-0 American style) and export
it as a RailBuilder-ready GLB + sidecar JSON.

RailBuilder asset contract this script guarantees:
  * units are meters at real scale (engine ~9 m long)
  * front of the engine points along Blender +Y  ->  Godot -Z (forward)
  * wheels rest on the ground plane (Blender Z=0  ->  Godot Y=0)
  * origin centered on the wheelbase, all transforms applied
  * one mesh, flat-color Principled materials, no textures (small file)
  * sidecar <name>.json written next to the GLB with the catalog metadata

Run headless:
    blender --background --python build_steam_engine.py -- /path/to/Assets/SteamEngine1800s.glb
or open Blender, paste into the Scripting tab, and Run (exports to the
current working directory as SteamEngine1800s.glb).
"""

import json
import math
import os
import sys

import bpy

# ---------------------------------------------------------------- output path

def _out_path() -> str:
    argv = sys.argv
    if "--" in argv and len(argv) > argv.index("--") + 1:
        return os.path.abspath(argv[argv.index("--") + 1])
    return os.path.join(os.getcwd(), "SteamEngine1800s.glb")

OUT_GLB = _out_path()

# ---------------------------------------------------------------- clean scene

for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for block in (bpy.data.meshes, bpy.data.materials):
    for item in list(block):
        block.remove(item)

# ---------------------------------------------------------------- materials

def make_mat(name, rgba, metallic=0.0, roughness=0.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m

MAT_IRON  = make_mat("IronBlack", (0.035, 0.035, 0.040, 1), metallic=0.55, roughness=0.65)
MAT_BRASS = make_mat("Brass",     (0.740, 0.520, 0.150, 1), metallic=1.00, roughness=0.35)
MAT_WOOD  = make_mat("CabRed",    (0.360, 0.095, 0.060, 1), metallic=0.00, roughness=0.85)
MAT_WHEEL = make_mat("WheelRed",  (0.300, 0.070, 0.050, 1), metallic=0.10, roughness=0.70)
MAT_ROOF  = make_mat("RoofGrey",  (0.100, 0.100, 0.105, 1), metallic=0.00, roughness=0.90)
MAT_STEEL = make_mat("Steel",     (0.250, 0.250, 0.270, 1), metallic=0.80, roughness=0.45)

PARTS = []

def _finish(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    PARTS.append(obj)
    return obj

def box(name, mat, size, loc, rot=(0, 0, 0)):
    # primitive_cube_add(size=1.0) yields a unit-edge cube, so scale = edge lengths.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    return _finish(obj, name, mat)

def cyl(name, mat, radius, depth, loc, rot=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, name, mat)

def cone(name, mat, r1, r2, depth, loc, rot=(0, 0, 0), verts=16):
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, name, mat)

def sphere(name, mat, radius, loc, zscale=1.0, segs=12):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segs, ring_count=max(6, segs // 2), radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = (1.0, 1.0, zscale)
    return _finish(obj, name, mat)

# ---------------------------------------------------------------- geometry
# Coordinates: +Y = front of engine, Z up, ground at Z=0, meters.
X90 = math.pi / 2  # rotate a Z-axis cylinder to lie along Y
Y90 = (0, math.pi / 2, 0)  # rotate a Z-axis cylinder to lie along X (axles/wheels)

# Frame + footplate
box("Footplate", MAT_IRON, (2.2, 8.2, 0.22), (0, -0.10, 1.40))
box("FrameBeam", MAT_IRON, (1.6, 7.6, 0.55), (0, -0.20, 1.05))

# Boiler with brass bands, smokebox at the front
cyl("Boiler", MAT_IRON, 0.78, 4.40, (0, 1.10, 2.30), rot=(X90, 0, 0))
for i, by in enumerate((0.10, 1.20, 2.30)):
    cyl(f"BoilerBand{i}", MAT_BRASS, 0.81, 0.08, (0, by, 2.30), rot=(X90, 0, 0))
cyl("Smokebox", MAT_IRON, 0.84, 1.00, (0, 3.60, 2.30), rot=(X90, 0, 0))
cyl("SmokeboxDoor", MAT_STEEL, 0.66, 0.10, (0, 4.12, 2.30), rot=(X90, 0, 0))

# Diamond smokestack (the 1800s signature) + brass cap
cone("Stack", MAT_IRON, 0.24, 0.60, 1.10, (0, 3.60, 3.60))
cyl("StackCap", MAT_BRASS, 0.64, 0.12, (0, 3.60, 4.20))

# Domes + bell along the boiler top
cyl("SteamDomeBase", MAT_BRASS, 0.46, 0.50, (0, 0.30, 3.25))
sphere("SteamDomeCap", MAT_BRASS, 0.46, (0, 0.30, 3.50), zscale=0.55)
cyl("SandDomeBase", MAT_IRON, 0.38, 0.42, (0, 1.55, 3.20))
sphere("SandDomeCap", MAT_IRON, 0.38, (0, 1.55, 3.41), zscale=0.55)
cyl("BellMount", MAT_BRASS, 0.05, 0.40, (0, 2.55, 3.25))
sphere("Bell", MAT_BRASS, 0.17, (0, 2.55, 3.32), zscale=1.1, segs=10)

# Cab (wood, rustic) + roof
box("Cab", MAT_WOOD, (2.30, 1.90, 2.00), (0, -3.00, 2.50))
box("CabRoof", MAT_ROOF, (2.70, 2.30, 0.14), (0, -3.00, 3.60))

# Headlamp box on the smokebox
box("Headlamp", MAT_STEEL, (0.55, 0.50, 0.62), (0, 3.95, 3.15))

# Cowcatcher / pilot: 4-sided cone rotated tip-forward (+Y). Its profile verts
# land on local X (world sideways) and local Y (world vertical after the X-rot),
# so flattening local Y keeps the bottom vertex at rail level instead of below it.
pilot = cone("Cowcatcher", MAT_WHEEL, 1.15, 0.03, 1.40, (0, 4.45, 0.72),
             rot=(-X90, 0, 0), verts=4)
pilot.scale = (1.0, 0.60, 1.0)

# Steam cylinders either side of the smokebox
for sx, side in ((-0.95, "L"), (0.95, "R")):
    cyl(f"SteamCyl{side}", MAT_IRON, 0.28, 1.10, (sx, 2.90, 1.00), rot=(X90, 0, 0), verts=12)

# Wheels: two big driver pairs (rear), two small leading pairs (front)
for wy, wn in ((-2.00, "A"), (-0.50, "B")):
    cyl(f"DriverAxle{wn}", MAT_STEEL, 0.09, 2.00, (0, wy, 0.80), rot=Y90, verts=8)
    for sx, side in ((-0.85, "L"), (0.85, "R")):
        cyl(f"Driver{wn}{side}", MAT_WHEEL, 0.80, 0.24, (sx, wy, 0.80), rot=Y90, verts=14)
        cyl(f"DriverHub{wn}{side}", MAT_BRASS, 0.16, 0.28, (sx, wy, 0.80), rot=Y90, verts=8)
for wy, wn in ((1.80, "A"), (2.90, "B")):
    cyl(f"PonyAxle{wn}", MAT_STEEL, 0.07, 2.00, (0, wy, 0.42), rot=Y90, verts=8)
    for sx, side in ((-0.85, "L"), (0.85, "R")):
        cyl(f"Pony{wn}{side}", MAT_WHEEL, 0.42, 0.20, (sx, wy, 0.42), rot=Y90, verts=12)

# Side rods linking the drivers
for sx, side in ((-1.00, "L"), (1.00, "R")):
    box(f"SideRod{side}", MAT_STEEL, (0.08, 1.90, 0.14), (sx, -1.25, 0.80))

# ---------------------------------------------------------------- join + origin

for obj in bpy.data.objects:
    obj.select_set(obj in PARTS)
bpy.context.view_layer.objects.active = PARTS[0]
bpy.ops.object.join()
engine = bpy.context.active_object
engine.name = "SteamEngine1800s"
engine.data.name = "SteamEngine1800s"

bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

engine.data.calc_loop_triangles()
tris = len(engine.data.loop_triangles)
dims = engine.dimensions  # (width X, length Y, height Z) in meters
print(f"Built {engine.name}: {tris} tris, "
      f"{dims.x:.2f} m wide x {dims.y:.2f} m long x {dims.z:.2f} m tall")

# ---------------------------------------------------------------- export

os.makedirs(os.path.dirname(OUT_GLB) or ".", exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT_GLB,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_yup=True,
)

sidecar = {
    "id": "steam_engine_1800s",
    "display_name": "1800s Steam Engine",
    "category": "engine",
    "length_m": round(dims.y, 2),
    "mass_kg": 30000,
    "forward_axis": "-z",
    "y_offset": 0.0,
}
sidecar_path = os.path.splitext(OUT_GLB)[0] + ".json"
with open(sidecar_path, "w") as f:
    json.dump(sidecar, f, indent=2)

print(f"Exported {OUT_GLB} ({os.path.getsize(OUT_GLB) / 1024:.0f} KB)")
print(f"Sidecar  {sidecar_path}")
