class_name ArcEdge
extends TrackEdge
## A curved piece of track: a circular arc of fixed radius and signed sweep angle.
##
## sweep > 0 turns left (CCW), sweep < 0 turns right (CW). The arc starts at the
## origin pose and the center lies perpendicular to the heading on the turn side.

var origin: Transform2D = Transform2D.IDENTITY
var radius: float = 1.0
var sweep: float = PI / 2.0  # signed radians

func _init(p_origin: Transform2D = Transform2D.IDENTITY, p_radius: float = 1.0, p_sweep: float = PI / 2.0) -> void:
	origin = p_origin
	radius = p_radius
	sweep = p_sweep

func length() -> float:
	return radius * absf(sweep)

func pose_at(s: float) -> Transform2D:
	var h := origin.get_rotation()
	var pos := origin.origin
	var sgn := signf(sweep)
	var fwd := Vector2.RIGHT.rotated(h)
	var left := Vector2(-fwd.y, fwd.x)          # 90 deg CCW from heading
	var center := pos + left * sgn * radius     # center is on the turn side
	var theta := sgn * (s / radius)             # angle traversed at arc-length s
	var new_pos := center + (pos - center).rotated(theta)
	return Transform2D(h + theta, new_pos)

func to_dict() -> Dictionary:
	return {
		"type": "arc",
		"id": id,
		"px": origin.origin.x,
		"py": origin.origin.y,
		"rot": origin.get_rotation(),
		"radius": radius,
		"sweep": sweep,
	}
