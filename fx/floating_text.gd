class_name FloatingText
extends Node2D

## 伤害数字 / 提示飘字：向上飘 + 淡出后自毁
## 由 combat 双方调用：FloatingText.spawn(parent, world_pos, text, color)

var _label: Label
var _life: float = 0.8
var _max_life: float = 0.8
var _velocity: Vector2 = Vector2(0.0, -45.0)

## 在世界坐标 world_pos 处生成飘字，挂到 parent 下（通常传 get_tree().current_scene）
static func spawn(parent: Node, world_pos: Vector2, text: String, color: Color) -> void:
	var ft := preload("res://fx/floating_text.gd").new()
	parent.add_child(ft)
	ft.global_position = world_pos
	ft._setup(text, color)

func _setup(text: String, color: Color) -> void:
	_label = Label.new()
	_label.text = text
	_label.modulate = color
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	add_child(_label)

func _process(delta: float) -> void:
	_life -= delta
	position += _velocity * delta
	if is_instance_valid(_label):
		_label.modulate.a = clampf(_life / _max_life, 0.0, 1.0)
	if _life <= 0.0:
		queue_free()
