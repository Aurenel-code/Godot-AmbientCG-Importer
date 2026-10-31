@tool
extends Control

const CONFIG = preload("res://addons/ambientcg/core/ambient_config.gd")

@onready var ask_before_download: CheckBox = %AskBeforeDownload
@onready var save_button: Button = %SaveButton

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
	load_settings()
	save_button.pressed.connect(_on_save_button_pressed)


func load_settings():
	for setting in path_edits:
		path_edits[setting].text = CONFIG.get_setting(setting, CONFIG.get_default(setting))
	ask_before_download.button_pressed = CONFIG.get_setting(
		CONFIG.SETTING_ASK_BEFORE_DOWNLOAD, true
	)


func _on_save_button_pressed() -> void:
	for setting in path_edits:
		CONFIG.set_setting(setting, path_edits[setting].text)
	CONFIG.set_setting(CONFIG.SETTING_ASK_BEFORE_DOWNLOAD, ask_before_download.button_pressed)

	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg:
		ambient_cg.logger.info("Settings saved successfully", "Settings")

	load_settings()
