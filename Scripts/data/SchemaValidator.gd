extends RefCounted
class_name SchemaValidator

## Minimal JSON-Schema subset validator for the project's data files.
## Supported keywords: type (string or array of types), enum, const, required,
## properties, additionalProperties (bool or schema), items, minItems, maxItems,
## minimum, maximum, exclusiveMinimum, exclusiveMaximum, minLength, pattern,
## $ref ("#/$defs/name", "Other.schema.json" or "Other.schema.json#/$defs/name").
## Every check collects all errors and returns {ok: bool, errors: Array[String], error: String}.

const SCHEMA_DIR := "res://Data/schemas/"

var _schema_cache: Dictionary = {}
var _regex_cache: Dictionary = {}

# --- Legacy API (kept for compatibility) -------------------------------------------------

func validate_record(record: Dictionary, required_keys: Array[String], schema_name: String) -> Dictionary:
	var errors: Array[String] = []
	for key in required_keys:
		if not record.has(key):
			errors.append("%s missing key: %s" % [schema_name, key])
	return _result(errors)

func validate_array_of_dict(data: Variant, required_keys: Array[String], schema_name: String) -> Dictionary:
	var errors: Array[String] = []
	if typeof(data) != TYPE_ARRAY:
		errors.append("%s must be an array" % schema_name)
		return _result(errors)
	for i in data.size():
		if typeof(data[i]) != TYPE_DICTIONARY:
			errors.append("%s[%d] must be an object" % [schema_name, i])
			continue
		var record_check: Dictionary = validate_record(data[i], required_keys, "%s[%d]" % [schema_name, i])
		errors.append_array(record_check.get("errors", []))
	return _result(errors)

# --- Schema API ------------------------------------------------------------------------

## Loads (and caches) a schema file from Data/schemas. Accepts "Name.schema.json" or a full res:// path.
## Returns {} and appends to `errors` (if given) on failure.
func load_schema(name_or_path: String, errors: Array = []) -> Dictionary:
	var path := name_or_path if name_or_path.begins_with("res://") else SCHEMA_DIR + name_or_path
	if _schema_cache.has(path):
		return _schema_cache[path]
	if not FileAccess.file_exists(path):
		errors.append("Schema file missing: %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		errors.append("Schema parse error %s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("Schema %s must be a JSON object" % path)
		return {}
	var schema: Dictionary = json.data
	_schema_cache[path] = schema
	return schema

## Validates `value` against `schema`. `root` is the schema file used to resolve "#/..." refs
## (defaults to `schema` itself).
func validate(value: Variant, schema: Dictionary, path: String = "$", root: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	_validate_node(value, schema, path, root if not root.is_empty() else schema, errors, 0)
	return _result(errors)

## Validates `value` against the schema file `schema_file` (e.g. "TraitDefinition.schema.json").
func validate_with_file(value: Variant, schema_file: String, path: String = "$") -> Dictionary:
	var errors: Array[String] = []
	var schema := load_schema(schema_file, errors)
	if schema.is_empty():
		return _result(errors)
	_validate_node(value, schema, path, schema, errors, 0)
	return _result(errors)

## Validates that `data` is an array whose every item matches the schema file (an item schema).
func validate_array_with_file(data: Variant, item_schema_file: String, path: String) -> Dictionary:
	var errors: Array[String] = []
	var schema := load_schema(item_schema_file, errors)
	if schema.is_empty():
		return _result(errors)
	if typeof(data) != TYPE_ARRAY:
		errors.append("%s: expected array, got %s" % [path, _type_label(data)])
		return _result(errors)
	for i in data.size():
		_validate_node(data[i], schema, "%s[%d]" % [path, i], schema, errors, 0)
	return _result(errors)

# --- Internals -------------------------------------------------------------------------

func _result(errors: Array[String]) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"error": errors[0] if not errors.is_empty() else ""
	}

func _validate_node(value: Variant, schema: Dictionary, path: String, root: Dictionary, errors: Array[String], depth: int) -> void:
	if depth > 32:
		errors.append("%s: schema recursion too deep" % path)
		return

	if schema.has("$ref"):
		var resolved := _resolve_ref(str(schema["$ref"]), root, errors, path)
		if resolved.is_empty():
			return
		_validate_node(value, resolved["schema"], path, resolved["root"], errors, depth + 1)
		# Sibling keywords next to $ref are applied too (2020-12 semantics).
		var rest := schema.duplicate()
		rest.erase("$ref")
		rest.erase("description")
		if rest.is_empty():
			return
		schema = rest

	if schema.has("type") and not _matches_type(value, schema["type"]):
		errors.append("%s: expected %s, got %s" % [path, _type_list_label(schema["type"]), _type_label(value)])
		return

	if schema.has("const") and not _json_equal(value, schema["const"]):
		errors.append("%s: must equal %s" % [path, JSON.stringify(schema["const"])])

	if schema.has("enum") and typeof(schema["enum"]) == TYPE_ARRAY:
		var found := false
		for option in schema["enum"]:
			if _json_equal(value, option):
				found = true
				break
		if not found:
			errors.append("%s: value %s not in enum %s" % [path, JSON.stringify(value), JSON.stringify(schema["enum"])])

	if _is_number(value):
		var n := float(value)
		if schema.has("minimum") and n < float(schema["minimum"]):
			errors.append("%s: %s is below minimum %s" % [path, str(value), str(schema["minimum"])])
		if schema.has("maximum") and n > float(schema["maximum"]):
			errors.append("%s: %s is above maximum %s" % [path, str(value), str(schema["maximum"])])
		if schema.has("exclusiveMinimum") and n <= float(schema["exclusiveMinimum"]):
			errors.append("%s: %s must be > %s" % [path, str(value), str(schema["exclusiveMinimum"])])
		if schema.has("exclusiveMaximum") and n >= float(schema["exclusiveMaximum"]):
			errors.append("%s: %s must be < %s" % [path, str(value), str(schema["exclusiveMaximum"])])

	if value is String or value is StringName:
		var s := str(value)
		if schema.has("minLength") and s.length() < int(schema["minLength"]):
			errors.append("%s: string shorter than %d" % [path, int(schema["minLength"])])
		if schema.has("pattern"):
			var re := _get_regex(str(schema["pattern"]))
			if re != null and re.search(s) == null:
				errors.append("%s: '%s' does not match pattern %s" % [path, s, str(schema["pattern"])])

	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if schema.has("minItems") and arr.size() < int(schema["minItems"]):
			errors.append("%s: expected at least %d items, got %d" % [path, int(schema["minItems"]), arr.size()])
		if schema.has("maxItems") and arr.size() > int(schema["maxItems"]):
			errors.append("%s: expected at most %d items, got %d" % [path, int(schema["maxItems"]), arr.size()])
		if schema.has("items") and typeof(schema["items"]) == TYPE_DICTIONARY:
			for i in arr.size():
				_validate_node(arr[i], schema["items"], "%s[%d]" % [path, i], root, errors, depth + 1)

	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if schema.has("required") and typeof(schema["required"]) == TYPE_ARRAY:
			for key in schema["required"]:
				if not dict.has(key):
					errors.append("%s: missing required key '%s'" % [path, str(key)])
		var props: Dictionary = schema.get("properties", {}) if typeof(schema.get("properties", {})) == TYPE_DICTIONARY else {}
		var additional: Variant = schema.get("additionalProperties", true)
		for key in dict.keys():
			var child_path := "%s.%s" % [path, str(key)]
			if props.has(key):
				if typeof(props[key]) == TYPE_DICTIONARY:
					_validate_node(dict[key], props[key], child_path, root, errors, depth + 1)
			elif typeof(additional) == TYPE_BOOL:
				if not additional:
					errors.append("%s: unknown key '%s'" % [path, str(key)])
			elif typeof(additional) == TYPE_DICTIONARY:
				_validate_node(dict[key], additional, child_path, root, errors, depth + 1)

func _resolve_ref(ref: String, root: Dictionary, errors: Array[String], path: String) -> Dictionary:
	var file_part := ref
	var pointer := ""
	var hash_idx := ref.find("#")
	if hash_idx >= 0:
		file_part = ref.substr(0, hash_idx)
		pointer = ref.substr(hash_idx + 1)
	var target_root := root
	if not file_part.is_empty():
		var load_errors: Array = []
		target_root = load_schema(file_part, load_errors)
		if target_root.is_empty():
			for e in load_errors:
				errors.append("%s: %s" % [path, str(e)])
			return {}
	var node: Variant = target_root
	if not pointer.is_empty():
		for part in pointer.trim_prefix("/").split("/", false):
			if typeof(node) != TYPE_DICTIONARY or not node.has(part):
				errors.append("%s: unresolvable $ref '%s'" % [path, ref])
				return {}
			node = node[part]
	if typeof(node) != TYPE_DICTIONARY:
		errors.append("%s: $ref '%s' is not a schema object" % [path, ref])
		return {}
	return {"schema": node, "root": target_root}

func _matches_type(value: Variant, type_spec: Variant) -> bool:
	if typeof(type_spec) == TYPE_ARRAY:
		for t in type_spec:
			if _matches_single_type(value, str(t)):
				return true
		return false
	return _matches_single_type(value, str(type_spec))

func _matches_single_type(value: Variant, t: String) -> bool:
	match t:
		"object":
			return typeof(value) == TYPE_DICTIONARY
		"array":
			return typeof(value) == TYPE_ARRAY
		"string":
			return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
		"number":
			return _is_number(value)
		"integer":
			if typeof(value) == TYPE_INT:
				return true
			if typeof(value) == TYPE_FLOAT:
				var f: float = value
				return is_finite(f) and is_equal_approx(f, roundf(f))
			return false
		"boolean":
			return typeof(value) == TYPE_BOOL
		"null":
			return typeof(value) == TYPE_NIL
	return true

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _json_equal(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	if typeof(a) != typeof(b):
		return false
	return a == b

func _get_regex(pattern: String) -> RegEx:
	if _regex_cache.has(pattern):
		return _regex_cache[pattern]
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		push_warning("SchemaValidator: invalid pattern %s" % pattern)
		re = null
	_regex_cache[pattern] = re
	return re

func _type_label(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return "object"
		TYPE_ARRAY:
			return "array"
		TYPE_STRING, TYPE_STRING_NAME:
			return "string"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_BOOL:
			return "boolean"
		TYPE_NIL:
			return "null"
	return type_string(typeof(value))

func _type_list_label(type_spec: Variant) -> String:
	if typeof(type_spec) == TYPE_ARRAY:
		return "/".join(PackedStringArray(type_spec))
	return str(type_spec)
