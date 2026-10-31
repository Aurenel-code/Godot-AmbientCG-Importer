extends GutTest

var Config = load("res://addons/ambientcg/core/ambient_config.gd")


func test_get_setting_default():
	var val = Config.get_setting("non_existent/setting", "default")
	assert_eq(val, "default")


func test_plugin_info():
	assert_ne(Config.get_plugin_name(), "")
	assert_ne(Config.get_plugin_version(), "")
	assert_ne(Config.HOME_URL, "")
	assert_ne(Config.BASE_DOMAIN, "")


func test_set_and_get_setting():
	var test_key = "ambientcg/test_setting"
	var test_val = "hello_world"
	Config.set_setting(test_key, test_val)
	assert_eq(Config.get_setting(test_key, ""), test_val)


func test_migrate_legacy_defaults():
	var key = Config.SETTING_HDRI_DIR
	var saved = ProjectSettings.get_setting(key)
	ProjectSettings.set_setting(key, "res://ambientcg/environments")
	Config.migrate_legacy_defaults()
	assert_eq(Config.get_setting(key, ""), Config.DEFAULT_HDRI_DIR)

	ProjectSettings.set_setting(key, "res://my/custom/dir")
	Config.migrate_legacy_defaults()
	assert_eq(Config.get_setting(key, ""), "res://my/custom/dir", "Custom paths are kept")

	ProjectSettings.set_setting(key, saved)
	ProjectSettings.save()
