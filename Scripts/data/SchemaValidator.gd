extends RefCounted
class_name SchemaValidator

func validate_record(record: Dictionary, required_keys: Array[String], schema_name: String) -> Dictionary:
	for key in required_keys:
		if not record.has(key):
			return {"ok": false, "error": "%s missing key: %s" % [schema_name, key]}
	return {"ok": true}

func validate_array_of_dict(data: Variant, required_keys: Array[String], schema_name: String) -> Dictionary:
	if typeof(data) != TYPE_ARRAY:
		return {"ok": false, "error": "%s must be an array" % schema_name}
	for i in data.size():
		if typeof(data[i]) != TYPE_DICTIONARY:
			return {"ok": false, "error": "%s[%d] must be an object" % [schema_name, i]}
		var record_check: Dictionary = validate_record(data[i], required_keys, "%s[%d]" % [schema_name, i])
		if not bool(record_check.get("ok", false)):
			return record_check
	return {"ok": true}
