@tool
extends Node

var config: Script
var utils: Script
var logger: Node
var signals: Node
var api: Node
var material_maker: Script
var sky_maker: Script
var decal_maker: Script
var model_maker: Script

var downloader: Node
var extractor: Node


func _ready() -> void:
	downloader = preload("res://addons/ambientcg/handlers/ambient_downloader.gd").new()
	extractor = preload("res://addons/ambientcg/handlers/ambient_extractor.gd").new()

	downloader.name = "Downloader"
	extractor.name = "Extractor"

	add_child(downloader)
	add_child(extractor)

	downloader.config = config
	downloader.logger = logger
	downloader.signals = signals
	downloader.api = api
	downloader.utils = utils

	extractor.config = config
	extractor.utils = utils
	extractor.logger = logger
	extractor.signals = signals
	extractor.material_maker = material_maker
	extractor.sky_maker = sky_maker
	extractor.decal_maker = decal_maker
	extractor.model_maker = model_maker


func download_file_from_data(file_information: Dictionary, source_window: Node) -> void:
	check_dirs()
	downloader.download_file_from_data(file_information, source_window)


func extract_all(
	source_file: String, target_path: String = "", options: Dictionary = {}
) -> PackedStringArray:
	return await extractor.extract_all(source_file, target_path, options)


func check_dirs() -> void:
	config.migrate_legacy_defaults()
	for setting in config.PATH_DEFAULTS:
		utils.ensure_dir(config.get_setting(setting, config.PATH_DEFAULTS[setting]))
