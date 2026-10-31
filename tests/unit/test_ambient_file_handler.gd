extends GutTest

var AmbientFileHandler = load("res://addons/ambientcg/handlers/ambient_file_handler.gd")
var _handler = null


func before_each():
	_handler = AmbientFileHandler.new()
	_handler.signals = load("res://addons/ambientcg/core/ambient_signals.gd").new()
	_handler.logger = load("res://addons/ambientcg/core/ambient_logger.gd").new()
	_handler.api = load("res://addons/ambientcg/core/ambient_api.gd").new()

	_handler.add_child(_handler.signals)
	_handler.add_child(_handler.logger)
	_handler.add_child(_handler.api)

	_handler.config = load("res://addons/ambientcg/core/ambient_config.gd")
	_handler.utils = load("res://addons/ambientcg/utils/ambient_utils.gd")
	_handler.material_maker = load("res://addons/ambientcg/handlers/ambient_material_maker.gd")
	_handler.environment_maker = load(
		"res://addons/ambientcg/handlers/ambient_environment_maker.gd"
	)
	_handler.decal_maker = load("res://addons/ambientcg/handlers/ambient_decal_maker.gd")
	_handler.model_maker = load("res://addons/ambientcg/handlers/ambient_model_maker.gd")

	add_child(_handler)


func after_each():
	_handler.free()


func test_check_dirs_logic():
	_handler.check_dirs()
	var path = _handler.config.get_setting(
		_handler.config.SETTING_DOWNLOAD_PATH, _handler.config.DEFAULT_DOWNLOAD_PATH
	)
	assert_true(DirAccess.dir_exists_absolute(path))


func test_extract_all_fails_on_missing_file():
	watch_signals(_handler.signals)
	await _handler.extract_all("user://non_existent.zip")
	assert_signal_emitted(_handler.signals, "extraction_failed")
