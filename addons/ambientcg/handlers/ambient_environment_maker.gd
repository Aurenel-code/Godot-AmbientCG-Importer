@tool
# AmbientEnvironmentMaker
# Writes Environment resources that use an ambientCG HDRI as the sky.

const Writer = preload("res://addons/ambientcg/handlers/ambient_resource_writer.gd")


static func find_panorama(files: PackedStringArray) -> String:
	for file in files:
		if file.get_extension().to_lower() in ["exr", "hdr"]:
			return file
	return ""


static func write_environment(path: String, files: PackedStringArray) -> Error:
	var panorama := find_panorama(files)
	if panorama.is_empty():
		return ERR_FILE_NOT_FOUND

	var writer := Writer.new()
	var sky_material = writer.sub(
		"PanoramaSkyMaterial", {"panorama": writer.ext("Texture2D", panorama)}
	)
	var sky = writer.sub("Sky", {"sky_material": sky_material})
	var props := {
		"background_mode": Environment.BG_SKY,
		"sky": sky,
		# ACES tone mapping is generally better for HDRIs
		"tonemap_mode": Environment.TONE_MAPPER_ACES,
		"glow_enabled": true,
	}
	return Writer.save_text(path, writer.build_resource("Environment", props))
