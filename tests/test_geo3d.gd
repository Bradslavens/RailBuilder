extends TestCase
## Geo3D: 2D->3D lift and car transform.

func test_lift_maps_to_xz_plane() -> void:
	var v := Geo3D.lift(Vector2(3, 5), 0.0)
	assert_true(v.is_equal_approx(Vector3(3, 0, 5)), "sim (x,y) -> world (x,0,y)")

func test_lift_with_height() -> void:
	var v := Geo3D.lift(Vector2(1, 2), 0.9)
	assert_true(v.is_equal_approx(Vector3(1, 0.9, 2)), "height goes to Y")

func test_car_transform_centered_between_bogies() -> void:
	var t := Geo3D.car_transform(Vector2(2, 0), Vector2(-2, 0), 0.9)
	assert_true(t.origin.is_equal_approx(Vector3(0, 0.9, 0)), "origin at bogie midpoint")

func test_car_transform_is_orthonormal() -> void:
	var t := Geo3D.car_transform(Vector2(4, 1), Vector2(1, -2), 0.9)
	var b := t.basis
	assert_approx(b.determinant(), 1.0, "right-handed orthonormal basis", 0.001)
	assert_approx(b.x.length(), 1.0, "x unit", 0.001)
	assert_approx(b.z.length(), 1.0, "z unit", 0.001)
