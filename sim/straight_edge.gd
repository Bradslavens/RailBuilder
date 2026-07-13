class_name StraightEdge
extends TrackEdge
## A straight piece of track: a line segment of fixed length from an origin pose.

var origin: Transform2D = Transform2D.IDENTITY
var len_m: float = 1.0

func _init(p_origin: Transform2D = Transform2D.IDENTITY, p_len: float = 1.0) -> void:
	origin = p_origin
	len_m = p_len

func length() -> float:
	return len_m

func pose_at(s: float) -> Transform2D:
	var h := origin.get_rotation()
	var fwd := Vector2.RIGHT.rotated(h)
	return Transform2D(h, origin.origin + fwd * s)

func to_dict() -> Dictionary:
	return {
		"type": "straight",
		"id": id,
		"px": origin.origin.x,
		"py": origin.origin.y,
		"rot": origin.get_rotation(),
		"len": len_m,
	}
