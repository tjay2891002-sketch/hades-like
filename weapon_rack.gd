class_name WeaponRack
extends Node2D

## 初始房间武器架：逐步解锁 + 开局选武器。
## 玩家在交互范围内按 F 触发 interact()：
## - 未解锁 → 花英灵碎片解锁（局外永久）
## - 已解锁 → 装备为开局武器（RunState.weapon_idx）
## 战斗中不可再切换（player.gd 已移除 weapon_switch）。玩家选完起始赐福后 SaveRoom 会把神像锁定，
## 但武器架 lock() 为空操作，保证开局仍能换武器。

@export var weapon_index: int = 0   ## 对应 Player.WEAPONS 下标

var _prompt: Label
var _meta_unlocked: bool = false
var _equipped: bool = false

func _ready() -> void:
	_meta_unlocked = MetaState.is_weapon_unlocked(weapon_index)
	_equipped = RunState.weapon_idx == weapon_index
	add_to_group("interactable")
	_build_visual()
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)
	if not RunState.weapon_changed.is_connected(_on_weapon_changed):
		RunState.weapon_changed.connect(_on_weapon_changed)

## 武器信息（名称）从 Player.WEAPONS 取
func _weapon() -> Dictionary:
	return Player.WEAPONS[weapon_index]

func _refresh_prompt() -> void:
	if _prompt == null:
		return
	if not _meta_unlocked:
		_prompt.text = "%s 解锁（%d 碎片）" % [InputDevice.hint(&"interact"), int(MetaState.UNLOCK_COSTS.get(MetaState.WEAPON_KEYS[weapon_index], 0))]
	elif _equipped:
		_prompt.text = "✓ 已装备"
	else:
		_prompt.text = InputDevice.hint(&"interact") + " 装备"

func _on_device_changed(_gamepad: bool) -> void:
	_refresh_prompt()

func _on_weapon_changed(idx: int) -> void:
	_equipped = idx == weapon_index
	_refresh_prompt()

func _build_visual() -> void:
	var w := _weapon()
	var base_color: Color = w.get("color", Color(1.0, 1.0, 1.0, 0.4))
	if not _meta_unlocked:
		base_color = Color(0.4, 0.4, 0.45, 0.5)
	var shape := Polygon2D.new()
	shape.name = "Diamond"
	shape.polygon = PackedVector2Array([
		Vector2(0.0, -30.0), Vector2(22.0, 0.0),
		Vector2(0.0, 30.0), Vector2(-22.0, 0.0),
	])
	shape.color = base_color
	add_child(shape)

	var label := Label.new()
	label.text = String(w["name"])
	label.position = Vector2(-34.0, -46.0)
	label.size = Vector2(68.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0, 1) if _meta_unlocked else Color(0.55, 0.55, 0.6, 1))
	add_child(label)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.position = Vector2(-42.0, 20.0)
	_prompt.size = Vector2(84.0, 16.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1))
	add_child(_prompt)
	_refresh_prompt()

## 玩家按 F：未解锁→花碎片解锁；已解锁→装备为开局武器
func interact(_player: Node) -> void:
	if not _meta_unlocked:
		_try_unlock()
		return
	RunState.set_weapon(weapon_index)
	AudioManager.play(&"confirm")
	preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -60.0), "装备：" + String(_weapon()["name"]), Color(1.0, 0.9, 0.4))

func _try_unlock() -> void:
	if MetaState.try_unlock_weapon(weapon_index):
		_meta_unlocked = true
		for c in get_children():
			c.queue_free()
		_build_visual()
		AudioManager.play(&"achievement")
		preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -60.0), "已解锁：" + String(_weapon()["name"]), Color(1.0, 0.85, 0.3))
	else:
		AudioManager.play(&"error")
		preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -60.0), "碎片不足", Color(1.0, 0.4, 0.4))

## SaveRoom 选完起始赐福后会对所有 interactable 调 lock()；武器保持可交互（开局还能换武器）
func lock() -> void:
	pass
