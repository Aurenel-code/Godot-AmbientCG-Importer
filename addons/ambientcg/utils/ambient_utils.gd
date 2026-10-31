@tool
extends Node

# Hosts (and their subdomains) the plugin is allowed to contact.
# ambientCG serves thumbnails and downloads from struffelproductions.com.
const TRUSTED_HOSTS: PackedStringArray = ["ambientcg.com", "struffelproductions.com"]


static func format_file_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.2f KiB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.2f MiB" % (float(bytes) / (1024.0 * 1024.0))
	return "%.2f GiB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))


static func ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


static func clean_dir_content(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		var dir = DirAccess.open(path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					dir.remove(file_name)
				file_name = dir.get_next()


static func get_resource_name_clean(path: String) -> String:
	return path.get_file().get_basename()


static func save_buffer(path: String, buffer: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(buffer)
		file.close()


static func get_url_host(url: String) -> String:
	if not url.begins_with("https://"):
		return ""
	var authority := url.substr(8).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	if authority.contains("@") or authority.contains("\\"):
		return ""
	return authority.get_slice(":", 0).to_lower()


static func is_trusted_url(url: String) -> bool:
	var host := get_url_host(url)
	if host.is_empty():
		return false
	for trusted in TRUSTED_HOSTS:
		if host == trusted or host.ends_with("." + trusted):
			return true
	return false


# Resolves a redirect Location header against the URL that returned it.
static func resolve_redirect(base_url: String, location: String) -> String:
	if location.begins_with("//"):
		return "https:" + location
	if location.begins_with("/"):
		return "https://" + base_url.substr(8).get_slice("/", 0) + location
	return location


# Replaces anything that is not a letter, digit, "_" or "-" so API values
# can never introduce path separators or ".." into a file name.
static func sanitize_file_component(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9_-]")
	return regex.sub(text, "_", true)


static func is_safe_file_name(file_name: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-][A-Za-z0-9_. -]*\\.[A-Za-z0-9]+$")
	return regex.search(file_name) != null
