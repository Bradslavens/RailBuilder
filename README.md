# RailBuilder

A build-in-2D, ride-in-3D model railroad game — classic rail-set pieces with
Factorio-style deterministic simulation. Built in **Godot 4** (GDScript), desktop-first.

## Architecture

The world is **data, not visuals**. A rendering-agnostic simulation core lives in
`sim/`, and views are read-only consumers of it. This keeps the 2D editor, the
future 3D ride view, save/load, and possible future multiplayer all decoupled.

```
sim/        Pure logic (RefCounted, no Node refs). Deterministic-ready.
  track_edge.gd / straight_edge.gd / arc_edge.gd   parametric track pieces
  track_graph.gd                                   network + snapping
  track_path.gd / path_builder.gd                  the 1-D "wire" trains ride
  consist.gd / car.gd                              trains: dynamics, health
  train_builder.gd                                 place/couple/split trains
  block_map.gd                                     signal blocks (union-find)
  collisions.gd                                    impact damage, never fatal
  world.gd                                         top-level sim state + tick()
  serializer.gd                                    World <-> dict <-> JSON
catalog/    Data-driven definitions
  piece_catalog.gd        track-piece palette (straight / curves)
  terrain_catalog.gd      paintable terrain types (grass...mountain)
  asset_scanner.gd / model_library.gd / model_def.gd   GLB asset registry
autoload/
  game_state.gd           owns the live World, runs the fixed-timestep tick loop
views/
  build2d/                top-down editor: asset dock + map (tools: track,
                          vehicles, signals, terrain paint)
  ride3d/                 3D ride view of the same world
tests/                    headless unit tests (run_tests.gd + test_*.gd)
```

**Coordinate convention:** the sim works on a 2D plane in meters. A pose is a
`Transform2D` (origin = position, rotation = heading). The 3D view will lift this
to the XZ plane (Y up). Track pieces are circular arcs + line segments, so
position/heading at any arc-length `s` is closed-form.

## Run the editor

```
godot4 --path .          # or open project.godot in the Godot 4 editor
```

Controls: pick a tool in the asset dock — track pieces (`1/2/3`), engines/cars,
block signals, terrain paint. Left-click applies the tool (track snaps to green
endpoints; vehicles snap onto rails and couple at train ends; signals toggle on
track joints; paint drags). `X` removes the car under the cursor (middle car
splits the train) · right-click deselect · `Del` remove last piece · right-drag
pan · wheel zoom · `Space` run/stop all trains · `S` save · `L` load · `Tab` 3D.

## Run the tests (TDD)

```
./run_tests.sh
# or:
godot4 --headless --path . --script res://tests/run_tests.gd
```

## Roadmap

1. **Track editor (2D)** — pieces, endpoint snapping, save/load ✅
2. Moving train — longitudinal physics, multi-car consist following ✅
3. 3D view — track models, terrain, cab/aerial/free cameras ✅
4. Trains & signals — player-built consists (place/couple/split), 3-aspect
   block signals, collisions with damage, terrain painting ✅ *(switch routing TBD)*
5. Structures — stations, tunnels, water towers, coal, buildings, placeable cameras
6. Economy — coal/water consumption, cargo load/unload, schedules
7. Consist builder, model library/store, paint shop, polish
