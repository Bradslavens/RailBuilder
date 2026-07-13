class_name Consist
extends RefCounted
## A train: an ordered list of cars riding a TrackPath, with simplified longitudinal
## dynamics. Because the train is constrained to the track, motion is 1-D — a single
## `distance` (front of train, arc-length) and `velocity`. Car poses are derived from
## the path, so cars follow curves correctly (bogie-per-end "beads on a wire").
##
## Deterministic-ready: tick() uses only its own state + dt, no engine/rendering refs.

const COUPLER_GAP := 0.6      # meters between adjacent cars
const HALF_WIDTH := 0.7       # meters, for rendering hints

# Longitudinal dynamics (arcade, per-mass-normalized for Phase 2 simplicity).
const MAX_ACCEL := 1.5        # m/s^2 tractive
const MAX_BRAKE := 2.5        # m/s^2
const ROLL_RESIST := 0.05     # m/s^2 constant rolling resistance
const DRAG_K := 0.0008        # m/s^2 per (m/s)^2 aerodynamic-ish drag

var path: TrackPath
var cars: Array[Car] = []
var distance: float = 0.0     # arc-length of the front of the train
var velocity: float = 0.0     # m/s

# Inputs (set by autopilot or, later, the player).
var throttle: float = 0.0     # 0..1
var brake: float = 0.0        # 0..1
var autopilot: bool = true
var target_speed: float = 8.0 # m/s when running (0 = stop)

# Signal enforcement: meters ahead of the front at which the train must stop
# (INF = line is clear). Recomputed by World every tick from block occupancy.
var stop_in: float = INF

# How this consist's path was built, for save/load (see TrainBuilder/Serializer).
var anchor_edge_id: int = -1
var anchor_reversed: bool = false

func total_length() -> float:
	var l := 0.0
	for i in range(cars.size()):
		l += cars[i].length_m
		if i < cars.size() - 1:
			l += COUPLER_GAP
	return l

func total_mass() -> float:
	var m := 0.0
	for c in cars:
		m += c.mass_kg
	return m

func tick(dt: float) -> void:
	if autopilot:
		_drive_autopilot()
	var a := throttle * MAX_ACCEL - brake * MAX_BRAKE
	if absf(velocity) > 0.0001:
		a -= ROLL_RESIST * signf(velocity)
		a -= DRAG_K * velocity * absf(velocity)
	var new_v := velocity + a * dt
	# Coasting/braking resistance must not push the train backwards through zero.
	if signf(new_v) != signf(velocity) and throttle == 0.0:
		new_v = 0.0
	velocity = new_v
	distance += velocity * dt

	if path == null:
		return
	var tl := path.total_length()
	if tl <= 0.0:
		return
	if path.is_loop:
		distance = fposmod(distance, tl)
	else:
		distance = clampf(distance, 0.0, tl)

func has_engine() -> bool:
	for c in cars:
		if c.kind == "engine":
			return true
	return false

## Worst car health as 0..1; damaged trains keep running, just slower.
func health_factor() -> float:
	var worst := 100.0
	for c in cars:
		worst = minf(worst, c.health)
	return clampf(worst / 100.0, 0.3, 1.0)

func _drive_autopilot() -> void:
	# No engine, no traction: an unpowered string of cars just brakes to rest.
	if not has_engine():
		throttle = 0.0
		brake = 0.5
		return
	# A red signal ahead: brake so the front stops before the boundary.
	if stop_in < INF:
		var brake_dist := velocity * velocity / (2.0 * MAX_BRAKE)
		if stop_in <= brake_dist + 0.8:
			throttle = 0.0
			brake = 1.0
			return
	var goal := target_speed * health_factor()
	if velocity < goal - 0.2:
		throttle = 1.0
		brake = 0.0
	elif velocity > goal + 0.2:
		throttle = 0.0
		brake = 0.3
	else:
		throttle = 0.0
		brake = 0.0

## Rendering hint: for each car, its two bogie positions (front/back) in world space,
## plus its kind. The body is drawn between the bogies so it hugs curves.
func car_placements() -> Array:
	var out := []
	if path == null:
		return out
	var cursor := distance   # front of the train
	for c in cars:
		var d_front := cursor
		var d_back := cursor - c.length_m
		out.append({
			"front": path.pose_at_distance(d_front).origin,
			"back": path.pose_at_distance(d_back).origin,
			"kind": c.kind,
			"model_id": c.model_id,
			"health": c.health,
		})
		cursor = d_back - COUPLER_GAP
	return out

## The train's footprint as per-edge intervals [{edge_id, a, b}] — the shared
## coordinate system used for coupling checks, block occupancy, and collisions.
func occupied_intervals() -> Array:
	if path == null or cars.is_empty():
		return []
	return path.map_interval(distance - total_length(), distance)

## World positions of the two coupler points (front of train, back of train).
func coupler_points() -> Dictionary:
	if path == null:
		return {}
	return {
		"front": path.pose_at_distance(distance).origin,
		"back": path.pose_at_distance(distance - total_length()).origin,
	}

## A ready-made demo train: one engine + three cars.
static func demo(p_path: TrackPath) -> Consist:
	var c := Consist.new()
	c.path = p_path
	c.cars.append(Car.new(9.0, 40000.0, "engine"))
	for _i in range(3):
		c.cars.append(Car.new(8.0, 20000.0, "car"))
	c.autopilot = true
	c.target_speed = 8.0
	return c
