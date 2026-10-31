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
