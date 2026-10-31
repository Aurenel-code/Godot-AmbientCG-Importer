extends GutTest

var Sidebar = load("res://addons/ambientcg/ui/sidebar/sidebar.gd")


func _impls(names: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in names:
		out.append({"local_file_name": n})
	return out


func test_pick_container_format_prefers_zip():
	var impls = _impls(["Wood01_1K-JPG.usdz", "Wood01_1K-JPG.zip"])
	assert_eq(Sidebar._pick_container_format(impls), "zip")


func test_pick_container_format_falls_back_to_available():
	var impls = _impls(["Wood01_1K-JPG.usdz", "Wood01_2K-JPG.usdz"])
	assert_eq(Sidebar._pick_container_format(impls), "usdz")


func test_pick_container_format_empty():
	assert_eq(Sidebar._pick_container_format(_impls([])), "")
