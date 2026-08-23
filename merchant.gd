class_name Merchant
extends Node2D

## 商人（Phase 2）：站在商人房中央的 F 交互物。
## 玩家走近按 F 打开商店界面（EventBus.shop_opened），具体买卖由 ShopUI 处理，
## 本节点只负责交互触发，不持有任何金币/商品状态。

var _label: Label

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("merchant")
	_build_visual()
	## 键盘/手柄切换时刷新交互键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)

func _build_visual() -> void:
	## 石像贴图（替代原蓝色块；商人无碰撞体，32×32 原尺寸即可）
	var base := Sprite2D.new()
	base.texture = preload("res://assets/sprites/tiles/statue_alt.png")
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(base)
	_label = Label.new()
	_label.text = "商人\n%s 打开商店" % InputDevice.hint(&"interact")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-60.0, 34.0)
	_label.size = Vector2(120.0, 50.0)
	add_child(_label)

## 键盘/手柄切换：刷新交互键名提示
func _on_device_changed(_gamepad: bool) -> void:
	if _label != null:
		_label.text = "商人\n%s 打开商店" % InputDevice.hint(&"interact")

## 玩家按 F 触发（Player._try_interact 调用）：打开商店界面
func interact(player: Node) -> void:
	var p := player as Player
	if p == null:
		return
	EventBus.shop_opened.emit()
