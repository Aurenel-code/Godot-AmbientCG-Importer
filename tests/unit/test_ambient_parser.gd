@tool
extends GutTest

var Parser = load("res://addons/ambientcg/core/ambient_parser.gd")


func test_parse_assets_complex():
	var mock_json = {
		"totalResults": 1,
		"assets":
		[
			{
				"id": "Wood01",
				"title": "Wood 01",
				"thumbnails": {"128-PNG": "https://ambientcg.com/thumb.png"},
				"downloads":
				[
					{
						"attributes": "1K-JPG",
						"url": "https://api.test/1k",
						"size": 100,
						"extension": "zip"
					}
				]
			}
		]
	}
	var results = Parser.parse_assets(mock_json)
	assert_eq(results.get("result_count_total"), 1)
	var assets = results.get("assets", [])
	assert_eq(assets.size(), 1)
	assert_eq(assets[0].get("id"), "Wood01")
	assert_eq(assets[0].get("title"), "Wood 01")
	assert_eq(assets[0].get("thumbnail"), "https://ambientcg.com/thumb.png")
	assert_true(assets[0].get("implementation_uris", {}).has("1K-JPG"))
	assert_eq(assets[0].get("download_data").size(), 1)
	assert_eq(assets[0].get("download_data")[0].get("local_file_name"), "Wood01_1K-JPG.zip")


func test_parse_assets_types_and_filters():
	var mock_json = {
		"assets":
		[
			{"id": "BricksSubstance008", "type": "substance", "downloads": []},
			{"id": "Terrain005", "type": "terrain", "downloads": []},
			{
				"id": "Leaking012A",
				"type": "decal",
				"downloads":
				[
					{"attributes": "1K-JPG-ANIMATED", "url": "https://ambientcg.com/a"},
					{"attributes": "1K-JPG", "url": "https://ambientcg.com/b", "extension": "zip"}
				]
			},
			{"id": "DayEnvironmentHDRI114", "downloads": []},
		]
	}
	var assets = Parser.parse_assets(mock_json).get("assets")
	assert_eq(assets.size(), 2, "Substance and terrain assets should be hidden")
	assert_eq(assets[0].get("asset_type"), "decal")
	assert_eq(assets[0].get("download_data").size(), 1, "Animated downloads should be hidden")
	assert_eq(assets[0].get("download_data")[0].get("asset_type"), "decal")
	assert_eq(assets[1].get("asset_type"), "hdri", "Falls back to the ID without a type")


func test_parse_assets_transparency_and_png_alternative():
	var mock_json = {
		"assets":
		[
			{
				"id": "Manhole",
				"type": "decal",
				"maps": ["color", "opacity"],
				"downloads":
				[
					{"attributes": "1K-JPG", "url": "https://ambientcg.com/j", "extension": "zip"},
					{"attributes": "1K-PNG", "url": "https://ambientcg.com/p", "extension": "zip"},
					{"attributes": "2K-JPG", "url": "https://ambientcg.com/j2", "extension": "zip"},
				]
			},
			{"id": "Graffiti", "type": "atlas", "maps": ["color"], "downloads": []},
			{"id": "Bricks", "type": "material", "maps": ["color", "normal"], "downloads": []},
		]
	}
	var assets = Parser.parse_assets(mock_json).get("assets")
	assert_true(assets[0].get("has_transparency"), "An opacity map means transparency")
	assert_true(assets[1].get("has_transparency"), "Atlases are always transparent")
	assert_false(assets[2].get("has_transparency"))

	var downloads = assets[0].get("download_data")
	assert_true(downloads[0].get("has_transparency"))
	assert_eq(downloads[0].get("png_alternative", {}).get("uri"), "https://ambientcg.com/p")
	assert_false(downloads[1].has("png_alternative"), "PNG downloads need no alternative")
	assert_false(downloads[2].has("png_alternative"), "No 2K PNG exists")


func test_api_info_to_option_button():
	var button = OptionButton.new()
	Parser.api_info_to_option_button(
		button, {"types": [{"label": "3D Model", "value": "3d-model"}]}
	)
	assert_eq(button.item_count, 2)
	assert_eq(button.get_item_text(1), "3D Model")
	assert_eq(button.get_item_metadata(1), "3d-model")
	button.free()


func test_parse_assets_sanitizes_untrusted_values():
	var mock_json = {
		"assets":
		[
			{
				"id": "../../addons/evil",
				"thumbnails": {"128-PNG": "https://evil.com/thumb.png"},
				"downloads":
				[{"attributes": "1K/../x", "url": "https://evil.com/a", "extension": "gd"}]
			}
		]
	}
	var asset = Parser.parse_assets(mock_json).get("assets")[0]
	assert_eq(asset.get("thumbnail"), "")
	var file_name = asset.get("download_data")[0].get("local_file_name")
	assert_false(file_name.contains("/"))
	assert_false(file_name.contains(".."))
