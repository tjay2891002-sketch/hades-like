class_name BossAoe
extends Node2D

## Boss 长距离大范围攻击：在 [param center] 显示红色预警圈，[param telegraph_time]
## 延迟后若玩家仍在圈内则造成伤害（逼迫翻滚躲避）。预警圈本身带闪烁提示。

@export var radius: float = 130.0
@export var damage: float = 28.0
@export var telegraph_time: float = 0.9
@export var center: Vector2 = Vector2.ZERO

var _ring: ColorRect
var _t: float = 0.0
var _done: bool = false

func _ready() -> void:
	add_to_group("boss_aoe")   ## Boss 死亡时统一清理
	global_position = center
	_ring = ColorRect.new()
	_ring.name = "Ring"
	_ring.size = Vector2(radius * 2.0, radius * 2.0)
	_ring.position = Vector2(-radius, -radius)
	_ring.color = Color(1.0, 0.2, 0.2, 0.22)
	add_child(_ring)

func _physics_process(_delta: float) -> void:
	if _done:
		return
	_t += _delta
	var ratio := clampf(_t / telegraph_time, 0.0, 1.0)
	# 预警圈随计时变红加深
	_ring.color.a = 0.22 + 0.5 * ratio
	if _t >= telegraph_time:
		_detonate()

func _detonate() -> void:
	_done = true
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		if player.global_position.distance_to(global_position) <= radius:
			player.take_damage(damage)
	# 爆裂闪一下再淡出
	_ring.color = Color(1.0, 0.3, 0.3, 0.6)
	var tw := create_tween()
	tw.tween_property(_ring, "modulate:a", 0.0, 0.25)
	await tw.finished
	if is_instance_valid(self):
		queue_free()
