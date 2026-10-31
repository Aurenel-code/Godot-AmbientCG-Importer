extends GutTest

const DIR = "user://test_texture_processor/"

var Processor = load("res://addons/ambientcg/handlers/ambient_texture_processor.gd")


func before_each():
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each():
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	DirAccess.remove_absolute(DIR)


func _save(file_name: String, image: Image) -> String:
	var path = DIR + file_name
	if path.ends_with(".jpg"):
		image.save_jpg(path, 1.0)
	else:
		image.save_png(path)
	return path


func _solid(size: int, format: Image.Format, color: Color) -> Image:
	var img = Image.create(size, size, false, format)
	img.fill(color)
	return img


func test_opacity_is_merged_into_color():
	var files: PackedStringArray = [
		_save("Set_1K-JPG_Color.jpg", _solid(8, Image.FORMAT_RGB8, Color.RED)),
		_save("Set_1K-JPG_Opacity.jpg", _solid(8, Image.FORMAT_L8, Color(0.4, 0.4, 0.4))),
	]
	var result = Processor.process_set(files, {})
	assert_eq(result, PackedStringArray([DIR + "Set_1K-JPG_Color.png"]), "JPG with alpha -> PNG")
	assert_false(FileAccess.file_exists(DIR + "Set_1K-JPG_Opacity.jpg"))
	assert_false(FileAccess.file_exists(DIR + "Set_1K-JPG_Color.jpg"))
	assert_almost_eq(Image.load_from_file(result[0]).get_pixel(0, 0).a, 0.4, 0.02)


func test_downscale_and_convert_to_webp():
	var files: PackedStringArray = [
		_save("Set_1K-PNG_Color.png", _solid(16, Image.FORMAT_RGB8, Color.BLUE)),
		_save("Set_1K-PNG_Roughness.png", _solid(16, Image.FORMAT_L8, Color(0.5, 0.5, 0.5))),
	]
	var options = {
		"target_size": 4,
		"convert_to": "webp_lossless",
		"source_attributes": "1K-PNG",
		"target_attributes": "512-WEBP-LOSSLESS",
	}
	var result = Processor.process_set(files, options)
	assert_eq(result[0], DIR + "Set_512-WEBP-LOSSLESS_Color.webp")
	assert_eq(Image.load_from_file(result[0]).get_size(), Vector2i(4, 4))
	assert_false(FileAccess.file_exists(files[0]), "The source file is replaced")
	assert_almost_eq(Image.load_from_file(result[1]).get_pixel(0, 0).r, 0.5, 0.01)


func test_model_material_file_points_at_processed_textures():
	var mtl = DIR + "Apple_LQ-1K-PNG.mtl"
	var file = FileAccess.open(mtl, FileAccess.WRITE)
	file.store_string("map_Kd Apple_LQ-1K-PNG_Color.png\n")
	file.close()
	var files: PackedStringArray = [
		mtl, _save("Apple_LQ-1K-PNG_Color.png", _solid(8, Image.FORMAT_RGB8, Color.RED))
	]
	var options = {
		"convert_to": "webp_lossless",
		"source_attributes": "LQ-1K-PNG",
		"target_attributes": "LQ-1K-WEBP-LOSSLESS",
	}
	Processor.process_set(files, options)
	assert_eq(FileAccess.get_file_as_string(mtl), "map_Kd Apple_LQ-1K-WEBP-LOSSLESS_Color.webp\n")


func test_flat_normals_stay_flat_and_keep_roughness():
	var img = _solid(16, Image.FORMAT_RGB8, Color(0.5, 0.5, 1.0))
	var lengths = Processor.downscale_normal_map(img, Vector2i(4, 4))
	assert_eq(img.get_size(), Vector2i(4, 4))
	assert_almost_eq(lengths[0], 1.0, 0.01)

	var rough = _solid(4, Image.FORMAT_L8, Color(0.5, 0.5, 0.5))
	Processor.add_normal_variance(rough, lengths)
	assert_almost_eq(rough.get_pixel(0, 0).r, 0.5, 0.01)


func test_lost_normal_detail_raises_roughness():
	# Normals tilted left and right in a checkerboard average to a short one.
	var img = Image.create(4, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 4:
			img.set_pixel(x, y, Color(0.85 if (x + y) % 2 == 0 else 0.15, 0.5, 0.85))
	var lengths = Processor.downscale_normal_map(img, Vector2i(1, 1))
	assert_lt(lengths[0], 0.95)
	assert_almost_eq(img.get_pixel(0, 0).b, 1.0, 0.01, "The averaged normal is renormalized")

	var rough = _solid(1, Image.FORMAT_L8, Color(0.3, 0.3, 0.3))
	Processor.add_normal_variance(rough, lengths)
	assert_gt(rough.get_pixel(0, 0).r, 0.35)


func test_fit_size_never_upscales():
	assert_eq(Processor.fit_size(Vector2i(1024, 512), 256), Vector2i(256, 128))
	assert_eq(Processor.fit_size(Vector2i(256, 256), 512), Vector2i(256, 256))
	assert_eq(Processor.fit_size(Vector2i(256, 256), 0), Vector2i(256, 256))
