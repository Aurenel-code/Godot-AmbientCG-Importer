@tool
extends PanelContainer

## Emitted once the download and import are over, with the history record.
signal finished(record: Dictionary)

const CONFIG = preload("res://addons/ambientcg/core/ambient_config.gd")
const UTILS = preload("res://addons/ambientcg/utils/ambient_utils.gd")
const STATUS_TEXT = {"completed": "Completed", "failed": "Failed"}
const STATUS_COLORS = {"completed": Color(0.45, 0.8, 0.45), "failed": Color(0.9, 0.4, 0.4)}
const TYPE_LABELS = {
	"material": "Material",
	"hdri": "HDRI",
	"decal": "Decal",
	"atlas": "Atlas",
	"3d-model": "3D Model",
}

var url: String = ""
var asset_name: String = ""
var asset_type: String = ""
var file_size: int = 0
var local_path: String = ""
var _is_extracting: bool = false
var _is_done: bool = false
# Set for past downloads, which only display their record.
var _record: Dictionary = {}

@onready var title_label: Label = %Title
@onready var status_label: Label = %Status
@onready var info_label: Label = %Info
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var show_button: Button = %ShowButton


func _ready() -> void:
	title_label.text = asset_name
	show_button.hide()
	show_button.pressed.connect(_on_show_pressed)
	if _record.is_empty():
		info_label.text = _format_info(asset_type, file_size, 0)
		_connect_signals_if_enabled()
	else:
		_apply_record()


func setup(p_url: String, p_name: String, p_asset_type: String = "", p_file_size: int = 0):
	url = p_url
	asset_name = p_name
	asset_type = p_asset_type
	file_size = p_file_size
	local_path = _build_download_path(p_name)
	if is_inside_tree():
		title_label.text = asset_name
		info_label.text = _format_info(asset_type, file_size, 0)


func setup_from_record(record: Dictionary) -> void:
	_record = record
	asset_name = str(record.get("name", ""))
	if is_inside_tree():
		_apply_record()


func _on_progress_updated(p_url: String, bytes_downloaded: int, total_bytes: int):
	if p_url == url and not _is_done:
		_update_progress(bytes_downloaded, total_bytes)


func _on_download_completed(p_path: String):
	if p_path == local_path and not _is_extracting and not _is_done:
		_is_extracting = true
		_start_extraction()


func _on_download_failed(p_url: String, reason: String) -> void:
	if p_url == url and not _is_extracting and not _is_done:
		_finish("failed", reason, "")


func _connect_signals_if_enabled() -> void:
	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg:
		ambient_cg.signals.download_progress_updated.connect(_on_progress_updated)
		ambient_cg.signals.download_completed.connect(_on_download_completed)
		ambient_cg.signals.download_failed.connect(_on_download_failed)


func _build_download_path(asset_name: String) -> String:
	var download_path = CONFIG.get_setting(
		CONFIG.SETTING_DOWNLOAD_PATH, CONFIG.DEFAULT_DOWNLOAD_PATH
	)
	return download_path.trim_suffix("/") + "/%s" % asset_name


func _update_progress(bytes_downloaded: int, total_bytes: int) -> void:
	var progress = (float(bytes_downloaded) / float(total_bytes)) * 100.0
	progress_bar.value = progress
	status_label.text = "Downloading (%.1f%%)" % progress
	info_label.text = (
		"%s / %s" % [UTILS.format_file_size(bytes_downloaded), UTILS.format_file_size(total_bytes)]
	)


func _start_extraction() -> void:
	status_label.text = "Importing..."
	progress_bar.hide()

	var created := PackedStringArray()
	var ambient_cg = CONFIG.get_instance(self)
	if ambient_cg:
		var extract_path = CONFIG.get_setting(
			CONFIG.SETTING_EXTRACT_PATH, CONFIG.DEFAULT_EXTRACT_PATH
		)
		created = await ambient_cg.file_handler.extract_all(
			local_path, extract_path, {"asset_type": asset_type}
		)

	if created.is_empty():
		_finish("failed", "Import failed", "")
	else:
		# Atlases are a folder of textures, so point at the folder.
		var path := created[0].get_base_dir() if asset_type == "atlas" else created[0]
		_finish("completed", "", path)


func _finish(status: String, detail: String, path: String) -> void:
	_is_done = true
	var record := {
		"name": asset_name,
		"asset_type": asset_type,
		"file_size": file_size,
		"status": status,
		"detail": detail,
		"path": path,
		"time": int(Time.get_unix_time_from_system()),
	}
	finished.emit(record)


func _apply_record() -> void:
	var status := str(_record.get("status", "failed"))
	var detail := str(_record.get("detail", ""))
	title_label.text = asset_name
	status_label.text = STATUS_TEXT.get(status, status.capitalize())
	if not detail.is_empty():
		status_label.text += ": " + detail
	status_label.add_theme_color_override(
		"font_color", STATUS_COLORS.get(status, STATUS_COLORS["failed"])
	)
	progress_bar.hide()
	info_label.text = _format_info(
		str(_record.get("asset_type", "")),
		int(_record.get("file_size", 0)),
		int(_record.get("time", 0))
	)
	var path := str(_record.get("path", ""))
	show_button.visible = (
		Engine.is_editor_hint()
		and not path.is_empty()
		and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path))
	)


func _on_show_pressed() -> void:
	var path := str(_record.get("path", ""))
	if Engine.is_editor_hint() and not path.is_empty():
		EditorInterface.get_file_system_dock().navigate_to_path(path)


static func _format_info(type: String, size: int, time: int) -> String:
	var parts := PackedStringArray()
	if not type.is_empty():
		parts.append(TYPE_LABELS.get(type, type.capitalize()))
	if size > 0:
		parts.append(UTILS.format_file_size(size))
	if time > 0:
		var bias: int = Time.get_time_zone_from_system().get("bias", 0)
		var date := Time.get_datetime_dict_from_unix_time(time + bias * 60)
		parts.append(
			(
				"%04d-%02d-%02d %02d:%02d"
				% [date["year"], date["month"], date["day"], date["hour"], date["minute"]]
			)
		)
	return " · ".join(parts)
