extends GutTest

var AmbientApi = load("res://addons/ambientcg/core/ambient_api.gd")
var _api = null


class MockManager:
	extends Node
	var api_information: Dictionary = {"categories": ["Material", "HDRI"]}


func before_each():
	_api = partial_double(AmbientApi).new()
	_api.config = load("res://addons/ambientcg/core/ambient_config.gd")
	_api.parser = load("res://addons/ambientcg/core/ambient_parser.gd")
	_api.logger = load("res://addons/ambientcg/core/ambient_logger.gd").new()
	_api.signals = load("res://addons/ambientcg/core/ambient_signals.gd").new()
	_api.manager = MockManager.new()
	_api.add_child(_api.logger)
	_api.add_child(_api.signals)
	_api.add_child(_api.manager)
	add_child(_api)


func after_each():
	_api.free()


func test_update_user_agent():
	_api.update_user_agent()
	assert_string_contains(_api.user_agent, "AmbientCG Plugin")


func test_http_request_invalid_url():
	var result = await _api.http_request(
		"invalid_url", PackedStringArray(), HTTPClient.METHOD_GET, ""
	)
	assert_eq(result[0], 1)


func test_search_assets_mocked():
	# Mock response from server
	var mock_response = [0, 200, {}, '{"assets": []}'.to_utf8_buffer()]
	stub(_api, "http_request").to_return(mock_response)

	var result = await _api.search_assets("wood", "Material")
	assert_typeof(result, TYPE_DICTIONARY)
	# result should be {"assets": []} parsed from our mock string
	assert_eq(result.get("assets"), [])


func test_search_assets_sends_sort():
	stub(_api, "http_request").to_return([0, 200, {}, "{}".to_utf8_buffer()])

	await _api.search_assets("wood", "Any", "", "", "latest")
	var url: String = get_call_parameters(_api, "http_request")[0]
	assert_string_contains(url, "&sort=latest")
	assert_false(url.contains("&type="), "'Any' type should not be sent")


func test_api_init_types():
	var values = _api.api_init().get("types").map(func(t): return t["value"])
	assert_false(values.has("substance"), "Substance should not be offered")
	assert_true(values.has("3d-model"), "API name for 3D models is '3d-model'")


func test_search_assets_omits_empty_sort():
	stub(_api, "http_request").to_return([0, 200, {}, "{}".to_utf8_buffer()])

	await _api.search_assets("wood")
	var url: String = get_call_parameters(_api, "http_request")[0]
	assert_false(url.contains("sort="))
