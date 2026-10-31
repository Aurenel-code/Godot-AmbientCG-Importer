@tool
extends Control

const CONFIG = preload("res://addons/ambientcg/core/ambient_config.gd")
const OPTIONS = preload("res://addons/ambientcg/core/ambient_download_options.gd")
const HDRI_SIZES = [1024, 2048, 4096, 8192, 16384]

# Setting key -> option button holding its import default.
var _default_options: Dictionary = {}

@onready var ask_before_download: CheckBox = %AskBeforeDownload
@onready var save_button: Button = %SaveButton
@onready var defaults_grid: GridContainer = %DefaultsGrid

# Setting key -> line edit holding its folder path.
@onready var path_edits = {
	CONFIG.SETTING_MATERIAL_DIR: %MatPath,
	CONFIG.SETTING_EXTRACT_PATH: %ExtPath,
	CONFIG.SETTING_HDRI_DIR: %EnvPath,
	CONFIG.SETTING_DECAL_DIR: %DecalPath,
	CONFIG.SETTING_MODEL_DIR: %ModelPath,
	CONFIG.SETTING_ATLAS_DIR: %AtlasPath,
	CONFIG.SETTING_DOWNLOAD_PATH: %DownPath,
}


func _ready() -> void:
	_build_import_defaults()
	load_settings()
	save_button.pressed.connect(_on_save_button_pressed)


func load_settings():
	for setting in path_edits:
		path_edits[setting].text = CONFIG.get_setting(setting, CONFIG.get_default(setting))
	ask_before_download.button_pressed = CONFIG.get_setting(
		CONFIG.SETTING_ASK_BEFORE_DOWNLOAD, true
	)
	for setting in _default_options:
		var options: OptionButton = _default_options[setting]
		var value = CONFIG.get_value(setting)
		for i in options.item_count:
			if options.get_item_metadata(i) == value:
				options.select(i)


func _on_save_button_pressed() -> void:
	for setting in path_edits:
		CONFIG.set_setting(setting, path_edits[setting].text)
	CONFIG.set_setting(CONFIG.SETTING_ASK_BEFORE_DOWNLOAD, ask_before_download.button_pressed)
	for setting in _default_options:
		var options: OptionButton = _default_options[setting]
		CONFIG.set_setting(setting, options.get_item_metadata(options.selected))

	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg:
		ambient_cg.logger.info("Settings saved successfully", "Settings")

	load_settings()


# The choices preselected in the import panel; each asset can still change them.
func _build_import_defaults() -> void:
	var formats := {}
	for format in OPTIONS.FORMATS:
		formats[format] = OPTIONS.FORMAT_LABELS[format]
	_add_default_row(CONFIG.SETTING_DEFAULT_FORMAT, "File Format", formats)
	_add_default_row(CONFIG.SETTING_DEFAULT_MODEL_QUALITY, "3D Model Quality", OPTIONS.LOD_LABELS)
	_add_default_row(CONFIG.SETTING_DEFAULT_HDRI_SIZE, "HDRI Resolution", _size_items(HDRI_SIZES))
	var texture_sizes := _size_items(OPTIONS.DOWNSCALE_SIZES)
	for channel in OPTIONS.CHANNELS:
		var label := "%s Resolution" % OPTIONS.CHANNEL_LABELS[channel]
		_add_default_row(CONFIG.channel_size_setting(channel), label, texture_sizes)


func _add_default_row(setting: String, label_text: String, items: Dictionary) -> void:
	var label := Label.new()
	label.text = label_text
	defaults_grid.add_child(label)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in items:
		options.add_item(items[value])
		options.set_item_metadata(options.item_count - 1, value)
	defaults_grid.add_child(options)
	_default_options[setting] = options


static func _size_items(sizes: Array) -> Dictionary:
	var items := {}
	for size in sizes:
		items[size] = OPTIONS.size_label(size)
	return items
