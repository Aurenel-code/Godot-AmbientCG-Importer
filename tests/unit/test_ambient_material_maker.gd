extends GutTest

var MaterialMaker = load("res://addons/ambientcg/handlers/ambient_material_maker.gd")


func test_make_standard_material_mapping():
	var dummy_color = "user://test_color.png"
	var dummy_normal = "user://test_normal.png"

	var img = Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	img.save_png(dummy_color)

	img.fill(Color(0.5, 0.5, 1.0))
	img.save_png(dummy_normal)

	var files: PackedStringArray = [dummy_color, dummy_normal]
	var options = {"use_triplanar_uv": false}

	var mat = MaterialMaker.make_standard_material(files, options)
	assert_not_null(mat, "Material should be created")
	assert_true(mat.normal_enabled, "Normal mapping should be enabled")

	mat = null

	DirAccess.remove_absolute(dummy_color)
	DirAccess.remove_absolute(dummy_normal)


func test_make_standard_material_prefers_gl_normal_and_sets_ao():
	var dummy_gl = "user://Test_1K-JPG_NormalGL.png"
	var dummy_dx = "user://Test_1K-JPG_NormalDX.png"
	var dummy_ao = "user://Test_1K-JPG_AmbientOcclusion.png"

	var img = Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.GREEN)
	img.save_png(dummy_gl)
	img.fill(Color.RED)
	img.save_png(dummy_dx)
	img.fill(Color.WHITE)
	img.save_png(dummy_ao)

	# DX listed last so it would win if it were not skipped.
	var files: PackedStringArray = [dummy_gl, dummy_ao, dummy_dx]
	var mat = MaterialMaker.make_standard_material(files, {})
	assert_true(mat.normal_enabled)
	var normal_pixel = mat.normal_texture.get_image().get_pixel(0, 0)
	assert_gt(normal_pixel.g, 0.5, "NormalGL should be used, not NormalDX")
	assert_true(mat.ao_enabled, "AO should be enabled")
	assert_not_null(mat.ao_texture)

	mat = null
	for path in [dummy_gl, dummy_dx, dummy_ao]:
		DirAccess.remove_absolute(path)


func test_make_standard_material_no_files():
	var mat = MaterialMaker.make_standard_material(PackedStringArray(), {})
	assert_not_null(mat)
	assert_false(mat.normal_enabled)
	mat = null
