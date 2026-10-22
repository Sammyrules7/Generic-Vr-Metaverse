class_name AvatarAssets
extends RefCounted
## Only catalog IDs cross the proxy boundary, never caller-supplied URLs.
static func url(id: String, kind: String) -> String:
	var entry := AvatarCatalog.definition(id)
	var source := str(entry.get("url" if kind == "model" else "thumbnail_url", ""))
	if source.is_empty() or kind not in ["model", "thumbnail"]:
		return ""
	var origin := str(ProjectSettings.get_setting("avatars/asset_origin", "https://app.vr.maio-tech.com"))
	return "%s/avatar-assets/%s/%s?v=%s" % [origin.trim_suffix("/"), id.uri_encode(), kind, source.sha256_text().left(16)]
