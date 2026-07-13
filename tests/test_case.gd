class_name TestCase
extends RefCounted
## Tiny dependency-free assertion base for headless unit tests. Test files extend
## this and define methods named test_*. See tests/run_tests.gd for the runner.

var _failures: Array[String] = []
var current_test: String = ""

func _fail(msg: String) -> void:
	_failures.append("%s: %s" % [current_test, msg])

func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		_fail(msg)

func assert_eq(a, b, msg: String = "") -> void:
	if a != b:
		_fail("%s (got %s, expected %s)" % [msg, str(a), str(b)])

func assert_approx(a: float, b: float, msg: String = "", eps: float = 0.001) -> void:
	if absf(a - b) > eps:
		_fail("%s (got %f, expected %f)" % [msg, a, b])

func assert_vec_approx(a: Vector2, b: Vector2, msg: String = "", eps: float = 0.01) -> void:
	if a.distance_to(b) > eps:
		_fail("%s (got %s, expected %s)" % [msg, str(a), str(b)])

func failures() -> Array[String]:
	return _failures
