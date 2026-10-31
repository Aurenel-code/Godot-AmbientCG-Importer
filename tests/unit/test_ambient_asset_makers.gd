extends GutTest

const DIR = "user://test_asset_makers/"

var Writer = load("res://addons/ambientcg/handlers/ambient_resource_writer.gd")
var EnvironmentMaker = load("res://addons/ambientcg/handlers/ambient_environment_maker.gd")
var DecalMaker = load("res://addons/ambientcg/handlers/ambient_decal_maker.gd")
var ModelMaker = load("res://addons/ambientcg/handlers/ambient_model_maker.gd")


func before_each():
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each():
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	DirAccess.remove_absolute(DIR)


func _save_image(name: String, color: Color, size := Vector2i(4, 2)) -> String:
	var img = Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	img.fill(color)
	img.save_png(DIR + name)
	return DIR + name


func test_writer_builds_resource_with_sub_resources():
	var writer = Writer.new()
	var tex = writer.ext("Texture2D", "res://a.png")
	var sub = writer.sub("Sky", {"sky_material": tex})
	var text = writer.build_resource("Environment", {"sky": sub, "glow_enabled": true})
	assert_string_contains(text, '[ext_resource type="Texture2D" path="res://a.png" id="1_ext"]')
	assert_string_contains(text, '[sub_resource type="Sky" id="1_sub"]')
	assert_string_contains(text, 'sky_material = ExtResource("1_ext")')
	assert_string_contains(text, 'sky = SubResource("1_sub")')
	assert_string_contains(text, "glow_enabled = true")
	assert_true(text.find("[sub_resource") < text.find("[resource]"))


func test_writer_output_loads_as_resource():
	var writer = Writer.new()
	var text = writer.build_resource("StandardMaterial3D", {"metallic": 0.5})
	Writer.save_text(DIR + "m.tres", text)
	var mat = ResourceLoader.load(DIR + "m.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(mat is StandardMaterial3D)
	assert_almost_eq(mat.metallic, 0.5, 0.001)


func test_environment_uses_exr_panorama():
	var files: PackedStringArray = [DIR + "Sky_1K_TONEMAPPED.jpg", DIR + "Sky_1K_HDR.exr"]
	assert_eq(EnvironmentMaker.write_environment(DIR + "env.tres", files), OK)
	var text = FileAccess.get_file_as_string(DIR + "env.tres")
	assert_string_contains(text, 'path="%sSky_1K_HDR.exr"' % DIR)
	assert_string_contains(text, '[sub_resource type="PanoramaSkyMaterial"')
	assert_string_contains(text, "background_mode = %d" % Environment.BG_SKY)


func test_environment_without_panorama_fails():
	var files: PackedStringArray = [DIR + "Sky_1K_TONEMAPPED.jpg"]
	assert_ne(EnvironmentMaker.write_environment(DIR + "env.tres", files), OK)


func test_decal_bakes_opacity_into_albedo_alpha():
	var files: PackedStringArray = [
		_save_image("Hole_1K-JPG_Color.png", Color.RED),
		_save_image("Hole_1K-JPG_Opacity.png", Color(0.2, 0.2, 0.2)),
		_save_image("Hole_1K-JPG_NormalGL.png", Color(0.5, 0.5, 1.0)),
		_save_image("Hole_1K-JPG_Roughness.png", Color(0.6, 0.6, 0.6)),
	]
	var err = DecalMaker.write_decal_scene(DIR + "decal.tscn", "Hole_1K-JPG", files, DIR)
	assert_eq(err, OK)

	var albedo = Image.load_from_file(DIR + "Hole_1K-JPG_DecalAlbedo.png")
	var pixel = albedo.get_pixel(0, 0)
	assert_almost_eq(pixel.r, 1.0, 0.01)
	assert_almost_eq(pixel.a, 0.2, 0.01, "Opacity should become the alpha channel")

	var orm = Image.load_from_file(DIR + "Hole_1K-JPG_DecalORM.png").get_pixel(0, 0)
	assert_almost_eq(orm.r, 1.0, 0.01, "Missing AO should be neutral")
	assert_almost_eq(orm.g, 0.6, 0.01, "Roughness goes in green")
	assert_almost_eq(orm.b, 0.0, 0.01, "Missing metalness should be zero")

	var text = FileAccess.get_file_as_string(DIR + "decal.tscn")
	assert_string_contains(text, '[node name="Hole_1K-JPG" type="Decal"]')
	assert_string_contains(text, "_DecalAlbedo.png")
	assert_string_contains(text, "texture_normal = ")
	assert_string_contains(text, "texture_orm = ")
	assert_string_contains(text, "size = Vector3(1, 1, 0.5)")


func test_decal_without_opacity_uses_color_directly():
	var files: PackedStringArray = [_save_image("Stain_1K-JPG_Color.png", Color.BLUE)]
	assert_eq(DecalMaker.write_decal_scene(DIR + "decal.tscn", "Stain", files, DIR), OK)
	var text = FileAccess.get_file_as_string(DIR + "decal.tscn")
	assert_string_contains(text, "Stain_1K-JPG_Color.png")
	assert_false(text.contains("texture_orm"))
	assert_false(FileAccess.file_exists(DIR + "Stain_DecalAlbedo.png"))


func test_decal_without_color_fails():
	var files: PackedStringArray = [_save_image("X_1K-JPG_Opacity.png", Color.WHITE)]
	assert_ne(DecalMaker.write_decal_scene(DIR + "decal.tscn", "X", files, DIR), OK)


func test_model_scene():
	var files: PackedStringArray = [DIR + "Apple_LQ-1K-JPG_Color.jpg", DIR + "Apple_LQ-1K-JPG.obj"]
	var mesh = ModelMaker.find_mesh(files)
	assert_eq(mesh, DIR + "Apple_LQ-1K-JPG.obj")

	var err = ModelMaker.write_model_scene(DIR + "apple.tscn", "Apple", mesh, "res://m.tres")
	assert_eq(err, OK)
	var text = FileAccess.get_file_as_string(DIR + "apple.tscn")
	assert_string_contains(text, '[node name="Apple" type="MeshInstance3D"]')
	assert_string_contains(text, 'path="%sApple_LQ-1K-JPG.obj"' % DIR)
	assert_string_contains(text, "material_override = ")


func test_model_scene_without_mesh_fails():
	assert_ne(ModelMaker.write_model_scene(DIR + "x.tscn", "X", "", ""), OK)
