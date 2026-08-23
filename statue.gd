class_name Statue
extends Node2D

## 存档房间雕像（R4）：单神神像。每座代表一位神明，供奉后从该神卡池随机抽 3 张三选一。
## 玩家在交互范围内按 F 触发 interact()，发 EventBus.boon_offer_requested(god, "")。
## 已解锁的神像默认“微微亮”，选中后亮度提升一档；只选一张，其余保持微微亮但不可再选。
## 未解锁的神像以灰暗“未解锁”占位显示，不可交互。

@export var god: StringName = &"宙斯"   ## 展示用神名
@export var card_id: StringName = &"zeus_chain"   ## 本雕像代表的卡（Boon.CARD_IDS 之一）
@export var unlock_key: StringName = &""   ## 局外解锁 key（= card_id 或 bonus_hp/bonus_gold）；起始神像留空即可
@export var unlocked: bool = true   ## true=无需碎片直接可用的起始神像；false=需碎片解锁（实际状态见 _meta_unlocked）

var _prompt: Label
var _sprite: Sprite2D
var _glow: Polygon2D
var _chosen: bool = false
var _locked: bool = false
var _meta_unlocked: bool = false   ## 综合 unlocked 与 MetaState 存档后的实际可用状态

func _ready() -> void:
	_meta_unlocked = unlocked or (unlock_key != &"" and MetaState.is_unlocked(unlock_key))
	if _meta_unlocked:
		_build_visual()
		if not _is_bonus():
			add_to_group("interactable")   ## 永久加成雕像是纯装饰，不进交互组
	else:
		add_to_group("interactable")   ## 未解锁雕像也可交互：按 F 花碎片解锁
		_build_locked_visual()
	## 常连：局中解锁的雕像同样要能响应 ESC 跳过恢复（handler 内有 _chosen 守卫，本就安全）
	if not EventBus.boon_offer_skipped.is_connected(_on_offer_skipped):
		EventBus.boon_offer_skipped.connect(_on_offer_skipped)
	## 键盘/手柄切换时刷新交互键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)

## 含键名的提示按当前输入设备刷新（"✓ 已选择"/"已选其他"/"永久加成已生效" 无键名，不在此维护）
func _refresh_prompt() -> void:
	if _prompt == null:
		return
	if not _meta_unlocked:
		_prompt.text = "%s 解锁（%d 碎片）" % [InputDevice.hint(&"interact"), int(MetaState.UNLOCK_COSTS.get(unlock_key, 0))]
	elif not _is_bonus() and not _chosen and not _locked:
		_prompt.text = InputDevice.hint(&"interact") + " 互动"

func _on_device_changed(_gamepad: bool) -> void:
	_refresh_prompt()

## 永久加成雕像（解锁后只是点亮的装饰，不提供选卡）
func _is_bonus() -> bool:
	return unlock_key == &"bonus_hp" or unlock_key == &"bonus_gold"

## 雕像代表内容的中文名（未解锁占位的展示用）：加成雕像写死文案，祝福雕像从卡工厂取卡名
func _content_name() -> String:
	if unlock_key == &"bonus_hp":
		return "坚韧·生命+25"
	if unlock_key == &"bonus_gold":
		return "丰盈·金币+15"
	if card_id == &"":
		return String(god)
	return Boon.make_boon(card_id).boon_name

## 已解锁神像：默认微微亮（淡金色光晕常显）+ 神名 + F 提示
func _build_visual() -> void:
	_glow = Polygon2D.new()
	_glow.name = "Glow"
	_glow.polygon = PackedVector2Array([
		Vector2(0.0, -52.0), Vector2(30.0, -10.0),
		Vector2(0.0, 34.0), Vector2(-30.0, -10.0),
	])
	_glow.color = Color(1.0, 0.85, 0.3, 0.18)   ## 默认“微微亮”
	_glow.visible = true
	add_child(_glow)

	## 石像贴图（替代原底座+头两个色块）：32×32 放大 1.5 倍对齐原 ~46px 高的视觉体量
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = preload("res://assets/sprites/tiles/statue.png")
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(1.5, 1.5)
	add_child(_sprite)

	var label := Label.new()
	label.text = _content_name() if _is_bonus() else String(god)
	label.position = Vector2(-30.0, -56.0)
	label.size = Vector2(60.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0, 1))
	add_child(label)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "永久加成已生效" if _is_bonus() else InputDevice.hint(&"interact") + " 互动"
	_prompt.position = Vector2(-30.0, 26.0)
	_prompt.size = Vector2(60.0, 16.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1))
	add_child(_prompt)

## 未解锁占位：暗灰雕像 + 内容名 + "X 解锁（N 碎片）"提示（X 随输入设备变化），仍进交互组（按交互键花碎片解锁）
func _build_locked_visual() -> void:
	## 石像贴图（替代原暗灰色块）：未解锁用 modulate 压暗表示占位
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = preload("res://assets/sprites/tiles/statue.png")
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(1.5, 1.5)
	_sprite.modulate = Color(0.45, 0.45, 0.5, 1)   ## 暗灰：未解锁
	add_child(_sprite)

	var label := Label.new()
	label.text = _content_name()
	label.position = Vector2(-30.0, -56.0)
	label.size = Vector2(60.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1))
	add_child(label)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "%s 解锁（%d 碎片）" % [InputDevice.hint(&"interact"), int(MetaState.UNLOCK_COSTS.get(unlock_key, 0))]
	_prompt.position = Vector2(-45.0, 26.0)
	_prompt.size = Vector2(90.0, 16.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 1))
	add_child(_prompt)

## 玩家按 F 触发：
## - 未解锁 → 花碎片解锁（碎片不足飘字提示）
## - 已解锁的祝福雕像 → 点亮、退出交互组、请求打开对应卡的赐福选择
## - 已解锁的加成雕像 → 纯装饰，不响应选卡
func interact(_player: Node) -> void:
	if not _meta_unlocked:
		_try_unlock()
		return
	if _chosen or _locked or _is_bonus():
		return
	_chosen = true
	_light_up()
	remove_from_group("interactable")
	EventBus.boon_offer_requested.emit(god, card_id)

## 未解锁雕像按 F：花碎片解锁。成功则拆掉灰暗占位、重建微微亮视觉并飘字提示；
## 失败飘字"碎片不足"（防"按了没反应"的困惑）
func _try_unlock() -> void:
	if MetaState.try_unlock(unlock_key):
		_meta_unlocked = true
		for c in get_children():
			c.queue_free()
		_build_visual()
		if _is_bonus():
			remove_from_group("interactable")   ## 加成雕像解锁后只是装饰
		AudioManager.play(&"achievement")
		preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -60.0), "已解锁：" + _content_name(), Color(1.0, 0.85, 0.3))
	else:
		AudioManager.play(&"error")
		preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -60.0), "碎片不足", Color(1.0, 0.4, 0.4))

## 选中后点亮：亮度提升（光晕更亮 + 贴图金色 modulate）+ 提示变更
func _light_up() -> void:
	_glow.visible = true
	_glow.color = Color(1.0, 0.88, 0.35, 0.5)   ## 较默认微微亮再提一档亮度
	_sprite.modulate = Color(1.0, 0.9, 0.5, 1)   ## 金色高亮
	_prompt.text = "✓ 已选择"
	_prompt.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1))

## 选卡被 ESC 跳过：本雕像已被点亮但玩家没拿到卡——恢复原样允许重新交互（防软锁）。
## 已成功选卡后 SaveRoom 会把其余雕像 lock()，此处不受影响。
func _on_offer_skipped() -> void:
	if not _chosen or _locked:
		return
	_chosen = false
	add_to_group("interactable")
	_glow.color = Color(1.0, 0.85, 0.3, 0.18)
	_sprite.modulate = Color(1.0, 1.0, 1.0, 1)   ## 恢复常态
	_prompt.text = InputDevice.hint(&"interact") + " 互动"
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1))

## 其余已解锁神像在玩家做出选择后锁定：保持微微亮，仅退出交互组、提示变更
func lock() -> void:
	if not _meta_unlocked:
		return   ## 未解锁雕像保持可解锁状态，不被"已选其他"误锁
	if _chosen:
		return
	_locked = true
	remove_from_group("interactable")
	if _glow != null:
		_glow.color = Color(1.0, 0.85, 0.3, 0.18)   ## 维持微微亮，不熄灭
	_prompt.text = "已选其他"
	_prompt.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1))
