class_name PickupItem
extends Area2D

## 消耗品掉落物（血瓶等）：怪物/Boss 掉落，玩家走近按交互键拾取入背包（RunState.inventory）。
## 与 DropItem（赐福宝石）并存：一个管消耗品，一个管祝福。

@export var item_id: StringName = &"potion"
@export var amount: int = 1

var _hint_label: Label

func _ready() -> void:
	add_to_group("interactable")
	## 键盘/手柄切换时刷新拾取键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)

	# 视觉：道具贴图（替代原色块瓶子；血瓶 potion.png，其余按 coin.png 兜底；缩到 24px 对齐原视觉）
	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = preload("res://assets/sprites/items/potion.png") if item_id == &"potion" else preload("res://assets/sprites/items/coin.png")
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.scale = Vector2(24.0, 24.0) / 32.0
	add_child(body)

	var shape := CircleShape2D.new()
	shape.radius = 14.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = Items.item_name(item_id) + " " + InputDevice.hint(&"interact") + " 拾取"
	hint.position = Vector2(-30.0, 14.0)
	hint.size = Vector2(80.0, 16.0)
	add_child(hint)
	_hint_label = hint

	# 漂浮动画只作用在视觉子节点上（同 DropItem 的教训：别碰根节点 position）
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(body, "position:y", -5.0, 0.55).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(body, "position:y", 0.0, 0.55).set_ease(Tween.EASE_IN_OUT)

## 键盘/手柄切换：刷新拾取键名提示
func _on_device_changed(_gamepad: bool) -> void:
	if _hint_label != null:
		_hint_label.text = Items.item_name(item_id) + " " + InputDevice.hint(&"interact") + " 拾取"

## 由 Player 的 F 交互系统调用：入背包 + 飘字 + 销毁
func interact(player: Node) -> void:
	RunState.add_item(item_id, amount)
	if player is Node2D:
		preload("res://fx/floating_text.gd").spawn(
			get_tree().current_scene,
			(player as Node2D).global_position + Vector2(0.0, -30.0),
			"+" + Items.item_name(item_id) + ("×" + str(amount) if amount > 1 else ""),
			Color(1.0, 0.6, 0.6))
	queue_free()
