extends GutTest

var Downloader = load("res://addons/ambientcg/handlers/ambient_downloader.gd")


func test_jpg_of_transparent_asset_needs_warning():
	assert_true(Downloader.needs_jpg_warning({"has_transparency": true, "attributes": "1K-JPG"}))


func test_png_or_opaque_assets_need_no_warning():
	assert_false(Downloader.needs_jpg_warning({"has_transparency": true, "attributes": "1K-PNG"}))
	assert_false(Downloader.needs_jpg_warning({"has_transparency": false, "attributes": "1K-JPG"}))
	assert_false(Downloader.needs_jpg_warning({"attributes": "1K-JPG"}))
