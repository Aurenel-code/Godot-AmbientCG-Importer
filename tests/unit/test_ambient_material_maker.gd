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


func _save_image(path: String, format: Image.Format, color: Color) -> String:
	var img = Image.create(4, 2, false, format)
	img.fill(color)
	img.save_png(path)
	return path


func test_opacity_map_is_baked_into_albedo_alpha():
	var dir = "user://test_material_alpha/"
	DirAccess.make_dir_recursive_absolute(dir)
	var files: PackedStringArray = [
		_save_image(dir + "Leaf_1K-JPG_Color.png", Image.FORMAT_RGB8, Color.GREEN),
		_save_image(dir + "Leaf_1K-JPG_Opacity.png", Image.FORMAT_RGB8, Color(0.3, 0.3, 0.3)),
	]
	assert_eq(MaterialMaker.write_standard_material(OUT_PATH, files, {}), OK)

	var baked = dir + "Leaf_1K-JPG_ColorAlpha.png"
	assert_almost_eq(Image.load_from_file(baked).get_pixel(0, 0).a, 0.3, 0.01)
	var text = FileAccess.get_file_as_string(OUT_PATH)
	assert_string_contains(text, 'path="%s"' % baked)
	assert_string_contains(
		text, "transparency = %d" % BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	)
	assert_string_contains(text, "cull_mode = %d" % BaseMaterial3D.CULL_DISABLED)

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)


func test_color_map_with_alpha_is_used_directly():
	var dir = "user://test_material_alpha/"
	DirAccess.make_dir_recursive_absolute(dir)
	var color = _save_image(dir + "Leaf_1K-PNG_Color.png", Image.FORMAT_RGBA8, Color(0, 1, 0, 0.5))
	var files: PackedStringArray = [
		color, _save_image(dir + "Leaf_1K-PNG_Opacity.png", Image.FORMAT_RGB8, Color.GRAY)
	]
	assert_eq(MaterialMaker.write_standard_material(OUT_PATH, files, {}), OK)
	assert_string_contains(FileAccess.get_file_as_string(OUT_PATH), 'path="%s"' % color)
	assert_false(FileAccess.file_exists(dir + "Leaf_1K-PNG_ColorAlpha.png"))

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)


func test_atlas_is_transparent_and_opaque_material_is_not():
	var maps = {"albedo": SET + "Color.jpg"}
	var atlas = MaterialMaker.build_material_properties(
		MaterialMaker.Writer.new(), maps, {"asset_type": "atlas"}
	)
	assert_true(atlas.has("transparency"))
	var opaque = MaterialMaker.build_material_properties(MaterialMaker.Writer.new(), maps, {})
	assert_false(opaque.has("transparency"))
