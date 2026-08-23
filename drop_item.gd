class_name DropItem
extends Area2D

## 精英击杀掉落奖励（Phase 3）。房间清空且为精英房时由 Room 生成在房间中心。
## 玩家走近（F 键交互范围内）按 F 拾取 -> 触发赐福选择。
## 防软锁：interact 后不立即销毁，先隐藏+禁用碰撞+退出交互组；
## 玩家按 ESC 跳过（boon_offer_skipped）时恢复原样，确认选到卡（boons_changed）后才销毁。
## [param god_filter] 为空=任意神卡池；指定神名=只在该神卡池抽（雕像可复用此机制）。

@export var god_filter: StringName = &""

var _col: CollisionShape2D
var _hint_label: Label
var _pending_offer: bool = false   ## true = 选卡界面打开中，等待"选卡/跳过"结果

func _ready() -> void:
	add_to_group("interactable")
	if not EventBus.boon_offer_skipped.is_connected(_on_offer_skipped):
		EventBus.boon_offer_skipped.connect(_on_offer_skipped)
	if not BoonManager.boons_changed.is_connected(_on_boons_changed):
		BoonManager.boons_changed.connect(_on_boons_changed)
	## 键盘/手柄切换时刷新拾取键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)

	# 视觉：赐福宝石贴图（替代原金色菱形；32×32 缩到 24px 对齐原视觉大小）
	var gem := Sprite2D.new()
	gem.name = "Gem"
	gem.texture = preload("res://assets/sprites/items/gem.png")
	gem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gem.scale = Vector2(24.0, 24.0) / 32.0
	add_child(gem)

	var shape := CircleShape2D.new()
	shape.radius = 14.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	_col = col

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = InputDevice.hint(&"interact") + " 拾取"
	hint.position = Vector2(-18.0, 14.0)
	add_child(hint)
	_hint_label = hint

	# 上下漂浮动画：只作用在视觉子节点 gem 上，绝不改根节点 position
	#（根节点 position 由 room.gd 的 global_position 设定，tween 抢改会导致菱形漂移）
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(gem, "position:y", -6.0, 0.6).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(gem, "position:y", 0.0, 0.6).set_ease(Tween.EASE_IN_OUT)

## 键盘/手柄切换：刷新拾取键名提示
func _on_device_changed(_gamepad: bool) -> void:
	if _hint_label != null:
		_hint_label.text = InputDevice.hint(&"interact") + " 拾取"

## 由 Player 的 F 交互系统调用：打开赐福选择（card_id 为空 = 不限定具体卡）。
## 不立即销毁：先隐藏并退出交互，等选卡结果——ESC 跳过则恢复，选到卡才 queue_free。
func interact(_player: Node) -> void:
	if _pending_offer:
		return
	_pending_offer = true
	visible = false
	remove_from_group("interactable")
	_col.set_deferred("disabled", true)
	EventBus.boon_offer_requested.emit(god_filter, &"")

## 选卡被 ESC 跳过：玩家没拿到卡——恢复宝石原样允许重新交互（防软锁，同 statue.gd 的模式）。
## 信号在 _ready 常连，未处于等待状态的宝石（_pending_offer=false）不受跳过/选卡事件影响。
func _on_offer_skipped() -> void:
	if not _pending_offer:
		return
	_pending_offer = false
	visible = true
	add_to_group("interactable")
	_col.set_deferred("disabled", false)

## 玩家真的选了卡（赐福集合变化）：本次 offer 完成，销毁宝石。
## 节点 free 时 Godot 4 自动断开其信号连接，无需手动 disconnect。
func _on_boons_changed(_count: int) -> void:
	if not _pending_offer:
		return
	queue_free()
