extends GutTest

var Utils = load("res://addons/ambientcg/utils/ambient_utils.gd")


func test_format_file_size():
	assert_eq(Utils.format_file_size(500), "500 B")
	assert_eq(Utils.format_file_size(1024), "1.00 KiB")
	assert_eq(Utils.format_file_size(1024 * 1024), "1.00 MiB")
	assert_eq(Utils.format_file_size(1024 * 1024 * 1024), "1.00 GiB")


func test_ensure_dir():
	var test_dir = "user://test_dir_creation/"
	Utils.ensure_dir(test_dir)
	assert_true(DirAccess.dir_exists_absolute(test_dir))
	# Cleanup
	DirAccess.remove_absolute(test_dir)


func test_clean_dir_content():
	var test_dir = "user://test_cleanup/"
	var test_file = test_dir + "dummy.txt"
	Utils.ensure_dir(test_dir)

	var f = FileAccess.open(test_file, FileAccess.WRITE)
	f.store_string("test")
	f.close()

	assert_true(FileAccess.file_exists(test_file))
	Utils.clean_dir_content(test_dir)
	assert_false(FileAccess.file_exists(test_file))

	# Cleanup
	DirAccess.remove_absolute(test_dir)


func test_is_trusted_url_accepts_ambientcg_hosts():
	assert_true(Utils.is_trusted_url("https://ambientcg.com/api/v3/assets"))
	assert_true(Utils.is_trusted_url("https://ambientcg.com/get?file=Bricks113A_1K-JPG.zip"))
	assert_true(Utils.is_trusted_url("https://acg-media.struffelproductions.com/file/thumb.png"))
	assert_true(Utils.is_trusted_url("https://acg-download.struffelproductions.com/x.zip"))
	assert_true(Utils.is_trusted_url("https://AmbientCG.com:443/api"))


func test_is_trusted_url_rejects_other_urls():
	assert_false(Utils.is_trusted_url(""))
	assert_false(Utils.is_trusted_url("invalid_url"))
	assert_false(Utils.is_trusted_url("http://ambientcg.com/api"))
	assert_false(Utils.is_trusted_url("https://evil.com/ambientcg.com"))
	assert_false(Utils.is_trusted_url("https://ambientcg.com.evil.com/"))
	assert_false(Utils.is_trusted_url("https://notambientcg.com/"))
	assert_false(Utils.is_trusted_url("https://ambientcg.com@evil.com/"))
	assert_false(Utils.is_trusted_url("https://evil.com\\@ambientcg.com/"))


func test_resolve_redirect():
	var base = "https://ambientcg.com/get?file=a.zip"
	assert_eq(Utils.resolve_redirect(base, "/file/a.zip"), "https://ambientcg.com/file/a.zip")
	assert_eq(Utils.resolve_redirect(base, "//cdn.example/a.zip"), "https://cdn.example/a.zip")
	assert_eq(Utils.resolve_redirect(base, "https://x.test/a.zip"), "https://x.test/a.zip")


func test_sanitize_file_component():
	assert_eq(Utils.sanitize_file_component("Bricks113A"), "Bricks113A")
	assert_eq(Utils.sanitize_file_component("1K-JPG"), "1K-JPG")
	assert_eq(Utils.sanitize_file_component("../../evil"), "______evil")
	assert_eq(Utils.sanitize_file_component("a/b\\c:d"), "a_b_c_d")


func test_is_safe_file_name():
	assert_true(Utils.is_safe_file_name("Bricks113A_1K-JPG.zip"))
	assert_true(Utils.is_safe_file_name("Bricks113A_1K-JPG_Color.jpg"))
	assert_false(Utils.is_safe_file_name(""))
	assert_false(Utils.is_safe_file_name(".."))
	assert_false(Utils.is_safe_file_name("..zip"))
	assert_false(Utils.is_safe_file_name("../evil.zip"))
	assert_false(Utils.is_safe_file_name("dir\\evil.zip"))
	assert_false(Utils.is_safe_file_name("C:evil.zip"))
	assert_false(Utils.is_safe_file_name("noextension"))
