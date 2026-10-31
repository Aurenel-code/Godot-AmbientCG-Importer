extends GutTest

const PATH = "user://test_download_history.json"

var Downloads = load("res://addons/ambientcg/ui/downloads/downloads.gd")
var DownloadItem = load("res://addons/ambientcg/ui/components/download/download_item.gd")


func after_each():
	DirAccess.remove_absolute(PATH)


func test_history_round_trip():
	var history = [
		{"name": "B.zip", "status": "failed", "detail": "Import failed", "time": 2},
		{"name": "A.zip", "status": "completed", "path": "res://a.tres", "time": 1},
	]
	Downloads.save_history(PATH, history)
	var loaded = Downloads.load_history(PATH)
	assert_eq(loaded.size(), 2)
	assert_eq(loaded[0].get("name"), "B.zip")
	assert_eq(loaded[1].get("path"), "res://a.tres")


func test_history_ignores_missing_or_broken_files():
	assert_eq(Downloads.load_history(PATH), [])
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	assert_eq(Downloads.load_history(PATH), [])


func test_history_skips_invalid_entries():
	var file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('[{"name": "A.zip"}, 5, "x"]')
	file.close()
	assert_eq(Downloads.load_history(PATH).size(), 1)


func test_format_info():
	assert_eq(DownloadItem._format_info("3d-model", 2048, 0), "3D Model · 2.05 KB")
	assert_eq(DownloadItem._format_info("", 0, 0), "")
