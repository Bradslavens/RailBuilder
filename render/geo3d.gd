class_name Geo3D
extends RefCounted
## Bridges the 2D simulation to the 3D presentation. The sim works on a plane in
## meters (Vector2, heading in radians); the 3D world puts that plane on XZ with Y up:
## sim (x, y)  ->  world (x, 0, y). Pure math, no scene refs — unit-testable.

## Lift a 2D sim point to a 3D world position at height y.
static func lift(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)

## The "right" direction (in the ground plane) for a given heading.
static func right_of(heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))

## Lift a full 2D sim pose to a 3D transform: origin on the XZ plane at height y,
## the pose's heading mapped to local -Z (Godot forward). Used to place track-piece
## models whose Entry sits at the model origin facing -Z.
static func pose_transform(pose: Transform2D, y: float = 0.0) -> Transform3D:
	var h := pose.get_rotation()
	var fwd := Vector3(cos(h), 0.0, sin(h))
	var zaxis := -fwd
	var xaxis := Vector3.UP.cross(zaxis).normalized()
	var yaxis := zaxis.cross(xaxis).normalized()
	return Transform3D(Basis(xaxis, yaxis, zaxis), lift(pose.origin, y))

## A transform for a car whose two bogies sit at front2d/back2d (sim coords).
## The body is centered between the bogies, its local -Z pointing along travel,
## so it hugs curves. Height y raises it onto the rails.
static func car_transform(front2d: Vector2, back2d: Vector2, y: float = 0.9) -> Transform3D:
	var f := lift(front2d, y)
	var b := lift(back2d, y)
	var center := (f + b) * 0.5
	var fwd := f - b
	if fwd.length() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var zaxis := -fwd                                  # forward is -Z (Godot convention)
	var xaxis := Vector3.UP.cross(zaxis).normalized()
	if xaxis.length() < 0.0001:
		xaxis = Vector3.RIGHT
	var yaxis := zaxis.cross(xaxis).normalized()
	return Transform3D(Basis(xaxis, yaxis, zaxis), center)
