class_name EnemyProjectile
extends Area2D

## 射手怪的飞弹：直线飞行，命中玩家造成伤害后消失；撞墙或超时消失。

@export var speed: float = 200.0
@export var damage: float = 8.0
@export var life_time: float = 3.0
@export var max_range: float = 300.0   ## 有效射程：飞满这么多像素即消散（射手防长距离对射）

var _velocity: Vector2 = Vector2.RIGHT
var _traveled: float = 0.0

func _ready() -> void:
	add_to_group("enemy_projectile")   ## 房间推进时由 Room 统一清理
	## 柔光高亮：敌弹在暗地板上不够醒目，先叠一层径向光晕
	var glow := _make_glow(32.0)
	glow.modulate = Color(1.0, 0.6, 0.45, 1.0)
	add_child(glow)
	## 法弹贴图 + 红色 modulate 区分敌我（替代原橙红色块）
	var gem := Sprite2D.new()
	gem.name = "Gem"
	gem.texture = preload("res://assets/sprites/fx/magic_bolt.png")
	gem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gem.scale = Vector2(16.0, 16.0) / 32.0   ## 略大于碰撞体，保证弹体本体可读
	gem.modulate = Color(1.0, 0.45, 0.3, 1.0)
	add_child(gem)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12.0, 12.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)

## 径向柔光：中心亮、边缘透明的光晕，用于给投射物加高亮
func _make_glow(radius: float) -> Sprite2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 64
	gtex.height = 64
	var s := Sprite2D.new()
	s.name = "Glow"
	s.texture = gtex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var scale_f := radius * 2.0 / 64.0
	s.scale = Vector2(scale_f, scale_f)
	return s

## 设定飞行方向（单位向量）
func launch(dir: Vector2) -> void:
	_velocity = dir.normalized() * speed

func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_traveled += speed * delta
	life_time -= delta
	if life_time <= 0.0 or _traveled >= max_range:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif body.is_in_group("wall"):
		queue_free()
