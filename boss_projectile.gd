class_name BossProjectile
extends Area2D

## Boss 弹幕飞镖：直线飞行，命中玩家造成伤害后消失；撞墙或超时也消失。
## 自身不属于 player/wall 组，故不会误伤 Boss 或互相触发。

@export var speed: float = 220.0
@export var damage: float = 12.0
@export var life_time: float = 4.0

var _velocity: Vector2 = Vector2.RIGHT

func _ready() -> void:
	add_to_group("boss_projectile")   ## Boss 死亡时统一清理
	## 法弹贴图 + 紫色 modulate 区分敌我（替代原紫色块）
	var gem := Sprite2D.new()
	gem.name = "Gem"
	gem.texture = preload("res://assets/sprites/fx/magic_bolt.png")
	gem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gem.scale = Vector2(14.0, 14.0) / 32.0   ## 与原色块同尺寸
	gem.modulate = Color(0.9, 0.4, 1.0, 1.0)
	add_child(gem)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14.0, 14.0)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)

## 设定飞行方向（单位向量）
func launch(dir: Vector2) -> void:
	_velocity = dir * speed

func _physics_process(delta: float) -> void:
	position += _velocity * delta
	life_time -= delta
	if life_time <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif body.is_in_group("wall"):
		queue_free()
