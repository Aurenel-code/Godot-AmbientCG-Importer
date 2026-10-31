@tool
extends Node

const UTILS = preload("res://addons/ambientcg/utils/ambient_utils.gd")
const MAX_API_RESPONSE_BYTES := 16 * 1024 * 1024
# HTTPRequest stores body_size_limit as a 32-bit int; larger values wrap
# around and make every download fail, so this is the highest usable cap.
const MAX_DOWNLOAD_BYTES := 2147483647
const DOWNLOAD_SIZE_TOLERANCE_BYTES := 1024 * 1024
const MAX_REDIRECTS := 5
const REDIRECT_CODES = [301, 302, 303, 307, 308]
const PAGE_SIZE := 100
# The API can only sort by downloads in descending order, so this sort walks
# that order backwards: pages are fetched from the end and reversed. Its
# "next page" links carry the offset where the next page ends.
const SORT_LEAST_DOWNLOADS := "least_downloads"
const REVERSED_PAGE_PREFIX := "reversed:"

var config: Script
var parser: Script
var logger: Node
var signals: Node
var manager: Node

var current_search_request: HTTPRequest = null
var user_agent := ""


func _ready() -> void:
	update_user_agent()


func update_user_agent() -> void:
	user_agent = (
		"AmbientCG Plugin (Godot %s)"
		% str(Engine.get_version_info().major, ".", Engine.get_version_info().minor)
	)


func http_request(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: HTTPClient.Method = 0,
	request_data: String = "",
	track_as_search: bool = false
):
	if not UTILS.is_trusted_url(url):
		logger.warn("Attempted to request invalid or untrusted URL: '%s'" % url, "Network")
		return [1, 0, {}, PackedByteArray()]

	var http_request = HTTPRequest.new()
	http_request.body_size_limit = MAX_API_RESPONSE_BYTES
	add_child(http_request)
	if track_as_search:
		current_search_request = http_request

	if custom_headers.is_empty():
		custom_headers.append("User-Agent: %s" % user_agent)
	else:
		var has_ua = false
		for h in custom_headers:
			if h.to_lower().begins_with("user-agent:"):
				has_ua = true
				break
		if not has_ua:
			custom_headers.append("User-Agent: %s" % user_agent)

	http_request.request(url, custom_headers, method, request_data)
	var response = await http_request.request_completed

	if track_as_search and current_search_request == http_request:
		current_search_request = null

	remove_child(http_request)
	http_request.queue_free()
	return response


func cancel_current_search() -> void:
	if current_search_request:
		current_search_request.cancel()
		current_search_request = null


func http_request_download(url: String, path: String, file_size: int) -> void:
	if url.is_empty():
		return

	# Redirects are followed manually so every hop can be checked against
	# the trusted host list before anything is written to disk.
	var success := false
	var current_url := url
	for _hop in MAX_REDIRECTS + 1:
		if not UTILS.is_trusted_url(current_url):
			if logger:
				logger.warn("Blocked download from untrusted URL: '%s'" % current_url, "Network")
			break

		var status = await _download_once(current_url, url, path, file_size)
		# With max_redirects = 0 a redirect response is reported as
		# RESULT_REDIRECT_LIMIT_REACHED, still carrying its code and headers.
		var result: int = status["result"]
		if (
			result != HTTPRequest.RESULT_SUCCESS
			and result != HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED
		):
			if logger and status["result"] == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
				logger.warn("Download exceeded the expected size and was stopped", "Network")
			break

		var code: int = status["code"]
		if code in REDIRECT_CODES:
			var location = _get_header(status["headers"], "location")
			if location.is_empty():
				break
			current_url = UTILS.resolve_redirect(current_url, location)
			continue

		success = code >= 200 and code < 300
		break

	if not success:
		DirAccess.remove_absolute(path)

	if success:
		if signals:
			signals.download_progress_updated.emit(url, file_size, file_size)
			signals.download_completed.emit(path)
	else:
		if signals:
			signals.download_failed.emit(url, "Download failed or connection lost")


func _download_once(
	request_url: String, progress_url: String, path: String, file_size: int
) -> Dictionary:
	var http_request = HTTPRequest.new()
	http_request.max_redirects = 0
	http_request.body_size_limit = _get_download_limit(file_size)
	http_request.download_file = path
	add_child(http_request)

	var status = {"finished": false, "result": -1, "code": 0, "headers": PackedStringArray()}
	http_request.request_completed.connect(
		func(result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray):
			status["finished"] = true
			status["result"] = result
			status["code"] = response_code
			status["headers"] = headers
	)

	var err = http_request.request(
		request_url, ["User-Agent: %s" % user_agent], HTTPClient.METHOD_GET, ""
	)
	if err != OK:
		status["finished"] = true

	while not status["finished"]:
		var downloaded = http_request.get_downloaded_bytes()
		if signals:
			var actual_total = max(file_size, downloaded) if file_size > 0 else max(1, downloaded)
			signals.download_progress_updated.emit(progress_url, downloaded, actual_total)
		await get_tree().create_timer(0.1).timeout

	remove_child(http_request)
	http_request.queue_free()
	return status


# Allows a small margin over the size reported by the API, never more than
# the hard cap, so a misbehaving server cannot fill the disk.
func _get_download_limit(file_size: int) -> int:
	if file_size <= 0:
		return MAX_DOWNLOAD_BYTES
	var margin = max(int(file_size * 0.1), DOWNLOAD_SIZE_TOLERANCE_BYTES)
	return min(file_size + margin, MAX_DOWNLOAD_BYTES)


func _get_header(headers: PackedStringArray, header_name: String) -> String:
	var prefix = header_name.to_lower() + ":"
	for header in headers:
		if header.to_lower().begins_with(prefix):
			return header.substr(prefix.length()).strip_edges()
	return ""


func search_assets(
	query: String,
	type: String = "",
	override_uri: String = "",
	exact_id: String = "",
	sort: String = ""
) -> Dictionary:
	if override_uri.begins_with(REVERSED_PAGE_PREFIX):
		var page := override_uri.trim_prefix(REVERSED_PAGE_PREFIX)
		return await _search_reversed(
			page.get_slice(":", 0).to_int(), page.substr(page.find(":") + 1)
		)

	var final_uri = ""
	if not override_uri.is_empty():
		final_uri = (
			override_uri if override_uri.begins_with("http") else config.BASE_DOMAIN + override_uri
		)
	else:
		final_uri = config.HOME_URL + "assets?include=downloads,thumbnails,type,maps"
		if not exact_id.is_empty():
			final_uri += "&id=" + exact_id.uri_encode()
		if not query.is_empty():
			final_uri += "&q=" + query.uri_encode()
		if not type.is_empty() and type != "Any":
			final_uri += "&type=" + type.to_lower().uri_encode()
		if sort == SORT_LEAST_DOWNLOADS:
			return await _search_reversed(-1, final_uri + "&sort=downloads")
		if not sort.is_empty():
			final_uri += "&sort=" + sort.uri_encode()
		final_uri += "&limit=%d" % PAGE_SIZE

	return await _get_json(final_uri)


# Fetches the page of base_uri's results that ends at offset `end` (-1 for
# the last page) in reverse order.
func _search_reversed(end: int, base_uri: String) -> Dictionary:
	if end < 0:
		var probe := await _get_json(base_uri + "&limit=1")
		if probe.is_empty():
			return {}
		end = int(probe.get("totalResults", 0))

	var offset := maxi(end - PAGE_SIZE, 0)
	var result := {"totalResults": 0, "assets": []}
	if end > 0:
		result = await _get_json(base_uri + "&limit=%d&offset=%d" % [end - offset, offset])
		if result.is_empty():
			return {}
	var assets: Array = result.get("assets", [])
	assets.reverse()
	result["assets"] = assets
	result["nextPageHttp"] = (
		"%s%d:%s" % [REVERSED_PAGE_PREFIX, offset, base_uri] if offset > 0 else ""
	)
	return result


func _get_json(uri: String) -> Dictionary:
	if not uri.is_empty():
		var response = await http_request(uri, PackedStringArray(), HTTPClient.METHOD_GET, "", true)
		if response[0] != HTTPRequest.RESULT_SUCCESS:
			return {}

		var json_string = response[3].get_string_from_utf8()
		return JSON.parse_string(json_string) if not json_string.is_empty() else {}

	return {}


func api_init() -> Dictionary:
	# "value" is the API's type name. Substance assets are left out because
	# Godot cannot use .sbsar files; terrains are left out for now.
	var types = [
		{"label": "Material", "value": "material"},
		{"label": "HDRI", "value": "hdri"},
		{"label": "Decal", "value": "decal"},
		{"label": "Atlas", "value": "atlas"},
		{"label": "3D Model", "value": "3d-model"},
	]
	var data = {"types": types}
	if manager:
		manager.api_information = data
	return data
