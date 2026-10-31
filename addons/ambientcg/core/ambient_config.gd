@tool

const SETTING_DOWNLOAD_PATH = "ambientcg/download_path"
const SETTING_EXTRACT_PATH = "ambientcg/extract_path"
const SETTING_MATERIAL_DIR = "ambientcg/material_file_directory"
const SETTING_HDRI_DIR = "ambientcg/environment_file_directory"
const SETTING_DECAL_DIR = "ambientcg/decal_file_directory"
const SETTING_MODEL_DIR = "ambientcg/model_file_directory"
const SETTING_ATLAS_DIR = "ambientcg/atlas_file_directory"
const SETTING_ASK_BEFORE_DOWNLOAD = "ambientcg/ask_before_download"
const SETTING_DEFAULT_FORMAT = "ambientcg/default_format"
const SETTING_DEFAULT_MODEL_QUALITY = "ambientcg/default_model_quality"
const SETTING_DEFAULT_HDRI_SIZE = "ambientcg/default_hdri_size"

const DEFAULT_DOWNLOAD_PATH = "res://ambientcg/temp"
const DEFAULT_EXTRACT_PATH = "res://ambientcg/extracted"
const DEFAULT_MATERIAL_DIR = "res://ambientcg/materials"
const DEFAULT_HDRI_DIR = "res://ambientcg/hdris"
const DEFAULT_DECAL_DIR = "res://ambientcg/decals"
const DEFAULT_MODEL_DIR = "res://ambientcg/models"
const DEFAULT_ATLAS_DIR = "res://ambientcg/atlases"

const PATH_DEFAULTS = {
	SETTING_DOWNLOAD_PATH: DEFAULT_DOWNLOAD_PATH,
	SETTING_EXTRACT_PATH: DEFAULT_EXTRACT_PATH,
	SETTING_MATERIAL_DIR: DEFAULT_MATERIAL_DIR,
	SETTING_HDRI_DIR: DEFAULT_HDRI_DIR,
	SETTING_DECAL_DIR: DEFAULT_DECAL_DIR,
	SETTING_MODEL_DIR: DEFAULT_MODEL_DIR,
	SETTING_ATLAS_DIR: DEFAULT_ATLAS_DIR,
}

# Defaults for the choices in the import panel. Texture resolutions are set
# per channel ("ambientcg/default_size_<channel>", see channel_size_setting).
const IMPORT_DEFAULTS = {
	SETTING_DEFAULT_FORMAT: "webp_lossless",
	SETTING_DEFAULT_MODEL_QUALITY: "SQ",
	SETTING_DEFAULT_HDRI_SIZE: 2048,
	"ambientcg/default_size_color": 1024,
	"ambientcg/default_size_normal": 2048,
	"ambientcg/default_size_roughness": 512,
	"ambientcg/default_size_metalness": 512,
	"ambientcg/default_size_ambient_occlusion": 512,
	"ambientcg/default_size_displacement": 512,
	"ambientcg/default_size_emission": 512,
}

# Earlier defaults that projects may still have saved; they are moved to the
# current default the next time the plugin checks its folders.
const LEGACY_PATH_DEFAULTS = {
	SETTING_HDRI_DIR: "res://ambientcg/environments",
}

const HOME_URL = "https://ambientcg.com/api/v3/"
const BASE_DOMAIN = "https://ambientcg.com"

const THEME_PATH = "res://addons/ambientcg/resources/themes/ambient_theme.tres"
const ICON_PATH = "res://addons/ambientcg/resources/icons/"

static var _cached_cfg: ConfigFile = null


static func get_setting(key: String, default_value: Variant) -> Variant:
	return ProjectSettings.get_setting(key, default_value)


static func get_default(key: String) -> Variant:
	return PATH_DEFAULTS.get(key, IMPORT_DEFAULTS.get(key))


## The saved value of a setting, or its default.
static func get_value(key: String) -> Variant:
	return get_setting(key, get_default(key))


## The setting holding the default resolution of a texture channel.
static func channel_size_setting(channel: String) -> String:
	return "ambientcg/default_size_" + channel.replace("-", "_")


static func migrate_legacy_defaults() -> void:
	for key in LEGACY_PATH_DEFAULTS:
		if ProjectSettings.has_setting(key) and get_setting(key, "") == LEGACY_PATH_DEFAULTS[key]:
			set_setting(key, PATH_DEFAULTS[key])


static func get_instance(node: Node) -> Node:
	if node.is_inside_tree():
		return node.get_node_or_null("/root/AmbientCG")
	return null


static func is_plugin_enabled() -> bool:
	return ProjectSettings.has_setting("autoload/AmbientCG")


static func set_setting(key: String, value: Variant) -> void:
	if key in PATH_DEFAULTS or key == SETTING_ASK_BEFORE_DOWNLOAD:
		if typeof(value) == TYPE_STRING:
			value = value.to_lower()
	ProjectSettings.set_setting(key, value)
	ProjectSettings.save()


static func _get_plugin_cfg() -> ConfigFile:
	if _cached_cfg:
		return _cached_cfg
	var config = ConfigFile.new()
	var err = config.load("res://addons/ambientcg/plugin.cfg")
	if err == OK:
		_cached_cfg = config
		return _cached_cfg
	return null


static func get_plugin_version() -> String:
	var cfg = _get_plugin_cfg()
	return cfg.get_value("plugin", "version", "0.0.0") if cfg else "0.0.0"


static func get_plugin_name() -> String:
	var cfg = _get_plugin_cfg()
	return cfg.get_value("plugin", "name", "AmbientCG") if cfg else "AmbientCG"
