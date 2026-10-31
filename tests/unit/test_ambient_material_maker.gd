extends GutTest

const OUT_PATH = "user://test_material.tres"
const SET = "res://ambientcg/extracted/Bricks113A_1K-JPG/Bricks113A_1K-JPG_"

var MaterialMaker = load("res://addons/ambientcg/handlers/ambient_material_maker.gd")


func after_each():
	DirAccess.remove_absolute(OUT_PATH)


func _full_set() -> PackedStringArray:
	return [
		SET + "Color.jpg",
		SET + "NormalDX.jpg",
		SET + "NormalGL.jpg",
		SET + "Roughness.jpg",
		SET + "Metalness.jpg",
		SET + "AmbientOcclusion.jpg",
		SET + "Displacement.jpg",
		SET + "Bricks113A.usdc",
	]


func test_classify_textures():
	var maps = MaterialMaker.classify_textures(_full_set())
	assert_eq(maps.get("albedo"), SET + "Color.jpg")
	assert_eq(maps.get("normal"), SET + "NormalGL.jpg", "NormalGL must be used, not NormalDX")
	assert_eq(maps.get("roughness"), SET + "Roughness.jpg")
	assert_eq(maps.get("metallic"), SET + "Metalness.jpg")
	assert_eq(maps.get("ao"), SET + "AmbientOcclusion.jpg")
	assert_eq(maps.get("height"), SET + "Displacement.jpg")
	assert_eq(maps.size(), 6)


func test_write_standard_material_text():
	assert_eq(MaterialMaker.write_standard_material(OUT_PATH, _full_set(), {}), OK)
	var text = FileAccess.get_file_as_string(OUT_PATH)

	assert_string_contains(text, '[gd_resource type="StandardMaterial3D" format=3]')
	assert_string_contains(text, 'path="%sColor.jpg"' % SET)
	assert_string_contains(text, 'path="%sNormalGL.jpg"' % SET)
	assert_false(text.contains("NormalDX"))
	assert_string_contains(text, "normal_enabled = true")
	assert_string_contains(text, "ao_enabled = true")
	assert_string_contains(text, "heightmap_enabled = true")
	assert_string_contains(text, "metallic = 1.0")


func test_write_standard_material_triplanar_skips_heightmap():
	MaterialMaker.write_standard_material(OUT_PATH, _full_set(), {"use_triplanar_uv": true})
	var text = FileAccess.get_file_as_string(OUT_PATH)
	assert_string_contains(text, "uv1_triplanar = true")
	assert_false(text.contains("heightmap"))


func test_write_standard_material_no_files():
	assert_eq(MaterialMaker.write_standard_material(OUT_PATH, PackedStringArray(), {}), OK)
	var text = FileAccess.get_file_as_string(OUT_PATH)
	assert_false(text.contains("ext_resource"))
	assert_false(text.contains("normal_enabled"))
