class_name BossExit
extends Area2D

## Boss 房唯一出口：Boss 存活时用实体墙封死，击杀后由 Boss 调 open_exit() 开启。
## 玩家走入后返回主流程（main.tscn）。击杀→开门→自行离场，节奏由玩家掌控。

var _blocker: StaticBody2D
var _visual: Polygon2D
var _label: Label
var _open: bool = false

func _ready() -> void:
	add_to_group("boss_exit")

	# 封门实体墙（开启前挡路，且入 wall 组挡弹幕/隔门刀）
	_blocker = StaticBody2D.new()
	_blocker.add_to_group("wall")
	var bshape := RectangleShape2D.new()
	bshape.size = Vector2(40.0, 20.0)
	var bcol := CollisionShape2D.new()
	bcol.shape = bshape
	_blocker.add_child(bcol)
	add_child(_blocker)

	# 门面视觉：封闭暗金色 → 开启后绿色半透明
	_visual = Polygon2D.new()
	_visual.polygon = PackedVector2Array([
		Vector2(-20.0, -10.0), Vector2(20.0, -10.0),
		Vector2(20.0, 10.0), Vector2(-20.0, 10.0),
	])
	_visual.color = Color(0.6, 0.5, 0.3, 1.0)
	add_child(_visual)

	# 检测区
	var ashape := RectangleShape2D.new()
	ashape.size = Vector2(48.0, 40.0)
	var acol := CollisionShape2D.new()
	acol.shape = ashape
	add_child(acol)
	monitoring = false
	body_entered.connect(_on_body_entered)

	_label = Label.new()
	_label.text = "出口（击杀 BOSS 后开启）"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-90.0, 16.0)
	_label.size = Vector2(180.0, 18.0)
	_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	add_child(_label)

func open_exit() -> void:
	if _open:
		return
	_open = true
	var col := _blocker.get_child(0) as CollisionShape2D
	if col != null:
		col.set_deferred("disabled", true)
	_blocker.remove_from_group("wall")
	_visual.color = Color(0.2, 0.7, 0.3, 0.45)
	set_deferred("monitoring", true)
	_label.text = "出口已开启 ↑ 离开"
	_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1))

func _on_body_entered(body: Node) -> void:
	if not _open or not body.is_in_group("player"):
		return
	# body_entered 处于 physics callback，切场景必须延迟
	call_deferred("_go")

func _go() -> void:
	get_tree().change_scene_to_file("res://main.tscn")
