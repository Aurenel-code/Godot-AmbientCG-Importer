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
	assert_eq(assets.size(), 2, "Substance assets should be hidden")
	assert_eq(assets[0].get("asset_type"), "decal")
	assert_eq(assets[0].get("download_data").size(), 1, "Animated downloads should be hidden")
	assert_eq(assets[0].get("download_data")[0].get("asset_type"), "decal")
	assert_eq(assets[1].get("asset_type"), "hdri", "Falls back to the ID without a type")


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
