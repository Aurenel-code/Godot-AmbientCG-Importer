@tool
# AmbientSkyMaker
# Writes PanoramaSkyMaterial resources that use an ambientCG HDRI.

const Writer = preload("res://addons/ambientcg/handlers/ambient_resource_writer.gd")


static func find_panorama(files: PackedStringArray) -> String:
	for file in files:
		if file.get_extension().to_lower() in ["exr", "hdr"]:
			return file
	return ""


static func write_sky_material(path: String, files: PackedStringArray) -> Error:
	var panorama := find_panorama(files)
	if panorama.is_empty():
		return ERR_FILE_NOT_FOUND

	var writer := Writer.new()
	var props := {"panorama": writer.ext("Texture2D", panorama)}
	return Writer.save_text(path, writer.build_resource("PanoramaSkyMaterial", props))
