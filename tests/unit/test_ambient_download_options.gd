extends GutTest

var Options = load("res://addons/ambientcg/core/ambient_download_options.gd")


func _downloads(attributes: Array) -> Array:
	var out := []
	for a in attributes:
		var download = {"asset_id": "Bricks", "attributes": a, "extension": "zip"}
		download["file_size"] = 1000
		out.append(download)
	return out


func test_parse_attributes():
	assert_eq(Options.parse_attributes("HQ-2K-PNG"), {"lod": "HQ", "size": 2048, "format": "PNG"})
	assert_eq(Options.parse_attributes("4K"), {"lod": "", "size": 4096, "format": ""})


func test_formats_need_their_source_set():
	var both = _downloads(["1K-JPG", "1K-PNG"])
	assert_eq(Options.get_formats(both), ["png", "jpg", "webp_lossless", "webp_lossy"])
	assert_eq(Options.get_formats(_downloads(["1K-JPG"])), ["jpg"], "WEBP is made from PNG")
	assert_eq(Options.get_formats(_downloads(["1K", "2K"])), [], "HDRIs have no format choice")


func test_sizes_include_downscaled_ones():
	var downloads = _downloads(["2K-PNG", "4K-PNG"])
	assert_eq(Options.get_sizes(downloads, "png", "", true), [256, 512, 1024, 2048, 4096])
	assert_eq(Options.get_sizes(downloads, "png", "", false), [2048, 4096])


func test_default_size_prefers_given_size_then_lower_then_higher():
	assert_eq(Options.pick_default_size([512, 1024, 2048, 4096], 2048), 2048)
	assert_eq(Options.pick_default_size([256, 512, 1024], 2048), 1024)
	assert_eq(Options.pick_default_size([4096, 8192], 2048), 4096)


func test_largest_channel_size_picks_the_set():
	var downloads = _downloads(["1K-PNG", "2K-PNG", "4K-PNG"])
	var sizes = {"color": 1024, "normal": 2048, "roughness": 512}
	var download = Options.build_download(downloads, "webp_lossless", "", 0, sizes)
	assert_eq(download["local_file_name"], "Bricks_2K-WEBP-LOSSLESS.zip")
	var options = download["import_options"]
	assert_eq(options["source_attributes"], "2K-PNG")
	assert_eq(options["channel_sizes"], sizes)


func test_channels_follow_the_asset_maps():
	assert_eq(Options.get_channels(["normal", "color", "opacity"]), ["color", "normal"])
	assert_eq(Options.get_channels([]), Options.COMMON_CHANNELS)
	assert_eq(Options.channel_of("res://x/Set_1K-PNG_Opacity.png"), "color")
	assert_eq(Options.channel_of("res://x/Set_1K-PNG_NormalGL.png"), "normal")
	assert_eq(Options.channel_of("res://x/Set_1K-PNG_AmbientOcclusion.jpg"), "ambient-occlusion")


func test_downscaled_choice_uses_next_larger_set():
	var downloads = _downloads(["1K-PNG", "2K-PNG", "4K-PNG"])
	var download = Options.build_download(downloads, "webp_lossless", "", 512)
	assert_eq(download["local_file_name"], "Bricks_512-WEBP-LOSSLESS.zip")
	var options = download["import_options"]
	assert_eq(options["source_attributes"], "1K-PNG")
	assert_eq(options["target_size"], 512)
	assert_eq(options["convert_to"], "webp_lossless")


func test_offered_size_is_not_rescaled():
	var download = Options.build_download(_downloads(["1K-JPG"]), "jpg", "", 1024)
	assert_eq(download["local_file_name"], "Bricks_1K-JPG.zip")
	assert_eq(download["import_options"]["target_size"], 0)
	assert_eq(download["import_options"]["convert_to"], "")


func test_model_quality_is_kept_in_the_name():
	var downloads = _downloads(["LQ-1K-PNG", "HQ-1K-PNG", "LQ-2K-PNG"])
	assert_eq(Options.get_lods(downloads), ["LQ", "HQ"])
	var download = Options.build_download(downloads, "webp_lossy", "LQ", 1024)
	assert_eq(download["local_file_name"], "Bricks_LQ-1K-WEBP-LOSSY.zip")
	assert_eq(download["import_options"]["source_attributes"], "LQ-1K-PNG")


func test_unavailable_choice_builds_nothing():
	assert_eq(Options.build_download(_downloads(["1K-JPG"]), "png", "", 1024), {})
