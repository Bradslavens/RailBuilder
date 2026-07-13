"""Build a low-poly rustic 1870s old-west passenger coach and export it as a
RailBuilder-ready GLB + sidecar JSON.

Same asset contract as build_steam_engine.py:
  * units are meters at real scale (coach ~11.6 m over the end platforms)
  * front of the car points along Blender +Y  ->  Godot -Z (forward)
  * wheels rest on the ground plane (Blender Z=0  ->  Godot Y=0)
  * origin centered between the trucks, all transforms applied
  * one mesh, flat-color Principled materials, no textures (small file)
  * sidecar <name>.json written next to the GLB with the catalog metadata

Run headless:
    blender --background --python build_passenger_car.py -- /path/to/PassengerCar_OldWest.glb
or open Blender, paste into the Scripting tab, and Run (exports to the
current working directory as PassengerCar_OldWest.glb).
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
    return os.path.join(os.getcwd(), "PassengerCar_OldWest.glb")

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

# Weathered varnished-wood coach: deep barn red body, cream trim, tarred roof.
MAT_BODY  = make_mat("CoachRed",   (0.290, 0.075, 0.055, 1), roughness=0.85)
MAT_TRIM  = make_mat("CreamTrim",  (0.720, 0.640, 0.480, 1), roughness=0.80)
MAT_ROOF  = make_mat("TarRoof",    (0.115, 0.105, 0.095, 1), roughness=0.92)
MAT_GLASS = make_mat("Glass",      (0.090, 0.115, 0.120, 1), metallic=0.30, roughness=0.20)
MAT_IRON  = make_mat("IronBlack",  (0.035, 0.035, 0.040, 1), metallic=0.55, roughness=0.65)
MAT_STEEL = make_mat("Steel",      (0.250, 0.250, 0.270, 1), metallic=0.80, roughness=0.45)
MAT_BRASS = make_mat("Brass",      (0.740, 0.520, 0.150, 1), metallic=1.00, roughness=0.35)
MAT_WHEEL = make_mat("WheelRust",  (0.230, 0.110, 0.070, 1), metallic=0.15, roughness=0.75)
MAT_DECK  = make_mat("DeckWood",   (0.330, 0.230, 0.150, 1), roughness=0.90)

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

def cyl(name, mat, radius, depth, loc, rot=(0, 0, 0), verts=12):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, name, mat)

# ---------------------------------------------------------------- geometry
# Coordinates: +Y = front of car, Z up, railhead at Z=0, meters.
Y90 = (0, math.pi / 2, 0)  # lay a Z-axis cylinder along X (axles and wheels)

BODY_HALF = 5.0    # body spans y = -5.0 .. +5.0
BODY_HW = 1.30     # body half-width
DECK_Z = 1.15      # floor height above railhead
BODY_TOP = 3.40    # eaves height
TRUCK_Y = 3.40     # trucks centered +/- this
WHEEL_R = 0.42

# --- underframe ---------------------------------------------------------
box("Underframe", MAT_IRON, (2.30, 10.60, 0.22), (0, 0, DECK_Z - 0.11))
box("Floor", MAT_DECK, (2.60, 10.00, 0.10), (0, 0, DECK_Z + 0.05))
# Truss rods with their queen posts — the giveaway of a wooden-framed car.
for sx, side in ((-0.80, "L"), (0.80, "R")):
    box(f"TrussRod{side}", MAT_STEEL, (0.06, 9.20, 0.06), (sx, 0, 0.72))
    for py in (-2.60, 0.0, 2.60):
        box(f"QueenPost{side}{py:+.0f}", MAT_STEEL, (0.08, 0.10, 0.34),
            (sx, py, 0.89))

# --- body shell ---------------------------------------------------------
box("BodySide L", MAT_BODY, (0.12, 10.00, BODY_TOP - DECK_Z - 0.10),
    (-BODY_HW + 0.06, 0, (DECK_Z + 0.10 + BODY_TOP) / 2))
box("BodySide R", MAT_BODY, (0.12, 10.00, BODY_TOP - DECK_Z - 0.10),
    (BODY_HW - 0.06, 0, (DECK_Z + 0.10 + BODY_TOP) / 2))
for ey, end in ((-BODY_HALF, "B"), (BODY_HALF, "F")):
    box(f"BodyEnd{end}", MAT_BODY, (2.60, 0.12, BODY_TOP - DECK_Z - 0.10),
        (0, ey, (DECK_Z + 0.10 + BODY_TOP) / 2))
    # End door + cream frame around it.
    box(f"EndDoorFrame{end}", MAT_TRIM, (1.00, 0.06, 1.95),
        (0, ey + math.copysign(0.08, ey), DECK_Z + 1.08))
    box(f"EndDoor{end}", MAT_DECK, (0.84, 0.06, 1.80),
        (0, ey + math.copysign(0.11, ey), DECK_Z + 1.02))
    box(f"EndDoorLight{end}", MAT_GLASS, (0.56, 0.04, 0.50),
        (0, ey + math.copysign(0.14, ey), DECK_Z + 1.60))

# Cream letterboard above the windows + a belt rail below them.
for sx, side in ((-BODY_HW - 0.01, "L"), (BODY_HW + 0.01, "R")):
    box(f"Letterboard{side}", MAT_TRIM, (0.05, 10.04, 0.34), (sx, 0, BODY_TOP - 0.20))
    box(f"BeltRail{side}", MAT_TRIM, (0.05, 10.04, 0.16), (sx, 0, DECK_Z + 0.62))
    box(f"Skirt{side}", MAT_TRIM, (0.05, 10.04, 0.12), (sx, 0, DECK_Z + 0.18))

# Windows: 6 per side, tall sashes with cream surrounds.
WIN_YS = [-3.75 + i * 1.50 for i in range(6)]
for sx, side in ((-BODY_HW, "L"), (BODY_HW, "R")):
    for i, wy in enumerate(WIN_YS):
        box(f"WinFrame{side}{i}", MAT_TRIM, (0.08, 1.00, 1.44), (sx, wy, DECK_Z + 1.42))
        box(f"WinGlass{side}{i}", MAT_GLASS, (0.10, 0.84, 1.26), (sx, wy, DECK_Z + 1.42))
        box(f"WinSash{side}{i}", MAT_TRIM, (0.11, 0.86, 0.05), (sx, wy, DECK_Z + 1.42))

# --- clerestory roof ----------------------------------------------------
# Lower roof deck, then the raised monitor with its little vent windows.
box("RoofDeck", MAT_ROOF, (2.86, 10.30, 0.14), (0, 0, BODY_TOP + 0.07))
box("ClerestoryBody", MAT_BODY, (1.56, 9.40, 0.40), (0, 0, BODY_TOP + 0.34))
box("ClerestoryCap", MAT_ROOF, (1.80, 9.60, 0.14), (0, 0, BODY_TOP + 0.61))
for sx, side in ((-0.79, "L"), (0.79, "R")):
    box(f"ClerestoryRail{side}", MAT_TRIM, (0.04, 9.40, 0.08), (sx, 0, BODY_TOP + 0.51))
    for i in range(9):
        vy = -4.00 + i * 1.00
        box(f"Vent{side}{i}", MAT_GLASS, (0.05, 0.60, 0.22), (sx, vy, BODY_TOP + 0.34))
# Roof vents / stove chimney (coaches were stove-heated).
cyl("StovePipe", MAT_IRON, 0.11, 0.55, (0.55, -4.20, BODY_TOP + 0.90), verts=8)
cyl("StoveCap", MAT_IRON, 0.16, 0.08, (0.55, -4.20, BODY_TOP + 1.19), verts=8)

# --- end platforms, railings, steps -------------------------------------
for ey, end, sgn in ((-BODY_HALF, "B", -1.0), (BODY_HALF, "F", 1.0)):
    py = ey + sgn * 0.40
    box(f"Platform{end}", MAT_DECK, (2.40, 0.80, 0.12), (0, py, DECK_Z + 0.03))
    box(f"PlatformSill{end}", MAT_IRON, (2.44, 0.84, 0.10), (0, py, DECK_Z - 0.06))
    # Corner posts + curved-look handrails (straight bars, kept low-poly).
    for sx, side in ((-1.14, "L"), (1.14, "R")):
        cyl(f"RailPost{end}{side}", MAT_STEEL, 0.045, 1.05,
            (sx, ey + sgn * 0.74, DECK_Z + 0.60), verts=6)
        box(f"HandRail{end}{side}", MAT_STEEL, (0.06, 0.80, 0.06),
            (sx, py + sgn * 0.02, DECK_Z + 1.10))
        box(f"RailGuard{end}{side}", MAT_STEEL, (0.06, 0.80, 0.04),
            (sx, py + sgn * 0.02, DECK_Z + 0.62))
        # Boarding steps hanging off each corner.
        box(f"Step{end}{side}A", MAT_IRON, (0.62, 0.34, 0.06),
            (sx * 0.86, py, DECK_Z - 0.30))
        box(f"Step{end}{side}B", MAT_IRON, (0.62, 0.34, 0.06),
            (sx * 0.86, py, DECK_Z - 0.66))
    # Brake wheel on the platform + coupler pocket and link-and-pin bar.
    cyl(f"BrakeStand{end}", MAT_IRON, 0.05, 1.20, (0.90, py, DECK_Z + 0.66), verts=6)
    cyl(f"BrakeWheel{end}", MAT_BRASS, 0.26, 0.05,
        (0.90, py, DECK_Z + 1.28), rot=(math.pi / 2, 0, 0), verts=10)
    box(f"Buffer{end}", MAT_IRON, (0.60, 0.30, 0.34), (0, ey + sgn * 0.95, 0.90))
    box(f"Coupler{end}", MAT_STEEL, (0.16, 0.44, 0.12), (0, ey + sgn * 1.28, 0.90))
    # Oil marker lamp at the rear-facing corner.
    box(f"MarkerLamp{end}", MAT_IRON, (0.24, 0.22, 0.30),
        (-1.10, ey + sgn * 0.72, DECK_Z + 1.42))
    box(f"MarkerLens{end}", MAT_BRASS, (0.26, 0.10, 0.16),
        (-1.10, ey + sgn * 0.80, DECK_Z + 1.42))

# --- trucks (two four-wheel bogies) -------------------------------------
for ty, tn in ((-TRUCK_Y, "B"), (TRUCK_Y, "F")):
    box(f"Bolster{tn}", MAT_IRON, (1.90, 0.44, 0.18), (0, ty, 0.86))
    for sx, side in ((-0.95, "L"), (0.95, "R")):
        box(f"TruckFrame{tn}{side}", MAT_IRON, (0.10, 2.30, 0.20), (sx, ty, 0.78))
    for ay, an in ((ty - 0.75, "A"), (ty + 0.75, "B")):
        cyl(f"Axle{tn}{an}", MAT_STEEL, 0.06, 1.90, (0, ay, WHEEL_R), rot=Y90, verts=8)
        for sx, side in ((-0.82, "L"), (0.82, "R")):
            cyl(f"Wheel{tn}{an}{side}", MAT_WHEEL, WHEEL_R, 0.16,
                (sx, ay, WHEEL_R), rot=Y90, verts=14)
            cyl(f"Hub{tn}{an}{side}", MAT_STEEL, 0.13, 0.20,
                (sx, ay, WHEEL_R), rot=Y90, verts=8)
            # Journal box rides outboard of the wheel face, clear of the tread.
            box(f"Journal{tn}{an}{side}", MAT_IRON, (0.16, 0.26, 0.26),
                (sx + math.copysign(0.16, sx), ay, WHEEL_R + 0.02))

# ---------------------------------------------------------------- join + origin

for obj in bpy.data.objects:
    obj.select_set(obj in PARTS)
bpy.context.view_layer.objects.active = PARTS[0]
bpy.ops.object.join()
car = bpy.context.active_object
car.name = "PassengerCar_OldWest"
car.data.name = "PassengerCar_OldWest"

bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

car.data.calc_loop_triangles()
tris = len(car.data.loop_triangles)
dims = car.dimensions  # (width X, length Y, height Z) in meters
print(f"Built {car.name}: {tris} tris, "
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
    "id": "passengercar_oldwest",
    "display_name": "Old West Passenger Car",
    "category": "car",
    "length_m": round(dims.y, 2),
    "mass_kg": 15000,
    "forward_axis": "-z",
    "y_offset": 0.0,
}
sidecar_path = os.path.splitext(OUT_GLB)[0] + ".json"
with open(sidecar_path, "w") as f:
    json.dump(sidecar, f, indent=2)

print(f"Exported {OUT_GLB} ({os.path.getsize(OUT_GLB) / 1024:.0f} KB)")
print(f"Sidecar  {sidecar_path}")
