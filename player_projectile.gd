class_name PlayerProjectile
extends Area2D

## 我方投射物（法杖飞弹 / 长弓箭矢 / 回旋盾）：直线飞行 + 可选寻敌转向，
## 命中敌人造成伤害并触发祝福（EventBus.hit_landed），撞墙或超时消失。
## 伤害在发射时已由 BoonManager.modify_attack_damage 修正完毕。
## - pierce：命中不消失，可贯穿多个敌人（每个敌人每程只吃一次）
## - homing_strength>0：自动寻敌（向 homing_range 内最近敌人转向）
## - aoe_radius>0：命中时爆发范围伤害（长弓蓄力）
## - boomerang：回旋盾——在敌人间弹射（最多 BOUNCE_MAX 个目标），撞墙即返航；
##   回程撞墙会沿墙面法线反弹、继续追踪玩家（任何一程都不穿墙）；
##   盾离手期间玩家无法攻击（由 Player 侧持有引用判定）

@export var speed: float = 380.0
@export var damage: float = 8.0
@export var life_time: float = 1.2
@export var pierce: bool = false
@export var tint: Color = Color(0.6, 0.8, 1.0, 1.0)
@export var homing_strength: float = 0.0   ## 寻敌转向加速度（px/s²），0=直线
@export var homing_range: float = 420.0
@export var aoe_radius: float = 0.0
@export var boomerang: bool = false
@export var visual_size: Vector2 = Vector2(10.0, 10.0)   ## 视觉/碰撞尺寸（回旋盾用大尺寸）
## true = 长弓箭矢（arrow.png，原图朝左需 flip_h）；false = 法杖飞弹（magic_bolt.png，原图朝东南需转正）；
## boomerang=true 时忽略本字段，固定用 shield.png
@export var is_arrow: bool = false

const BOOMERANG_OUT_TIME: float = 0.5   ## 回旋盾 outward 飞行时长
const BOOMERANG_RETURN_ACCEL: float = 1600.0
const BOUNCE_MAX: int = 3               ## 回旋盾去程最多弹射的目标数
const CATCH_DISTANCE: float = 24.0      ## 回到玩家手中判定距离
const AOE_DAMAGE_MULT: float = 0.6      ## 范围伤害对直接命中者之外敌人的倍率

const TEX_ARROW := preload("res://assets/sprites/fx/arrow.png")
const TEX_MAGIC := preload("res://assets/sprites/fx/magic_bolt.png")
const TEX_SHIELD := preload("res://assets/sprites/items/shield.png")

var _velocity: Vector2 = Vector2.RIGHT
var _hit_bodies: Array[Node] = []   ## 本程已命中的敌人，防止同一目标多次结算
var _returning: bool = false
var _fly_time: float = 0.0
var _prev_position: Vector2 = Vector2.ZERO   ## 上帧位置：撞墙时回退，防止嵌进墙体

func _ready() -> void:
	add_to_group("player_projectile")   ## 房间推进时由 Room 统一清理
	collision_mask = 3   ## 敌人挪到层 2 后投射物必须含层 2（层 1 仍能打 Boss/撞墙）
	## 贴图视觉（替代原色块）：回旋盾=盾、箭=箭（翻转到朝右）、法弹=法弹（转正到 +x），
	## 尺寸按原 visual_size 缩放（贴图均为 32×32），tint 染色保留（长弓蓄力绿等）
	## 柔光高亮：本方弹体在暗地板上不够醒目，先叠一层径向光晕
	var glow := _make_glow(maxf(visual_size.x, visual_size.y) * 2.6)
	glow.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	add_child(glow)
	var gem := Sprite2D.new()
	gem.name = "Gem"
	gem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gem.scale = visual_size / 32.0
	gem.modulate = tint
	if boomerang:
		gem.texture = TEX_SHIELD
	elif is_arrow:
		gem.texture = TEX_ARROW
		gem.flip_h = true   ## arrow.png 原图朝左，翻转成朝 +x，之后根节点随 velocity 旋转
	else:
		gem.texture = TEX_MAGIC
		gem.rotation = -PI * 0.25   ## magic_bolt.png 原图朝东南（45°），转正到 +x
	add_child(gem)
	var shape := RectangleShape2D.new()
	shape.size = visual_size
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)
	_prev_position = global_position

## 设定飞行方向（单位向量）；p_speed>0 时覆盖默认弹速
func launch(dir: Vector2, p_speed: float = 0.0) -> void:
	if p_speed > 0.0:
		speed = p_speed
	_velocity = dir.normalized() * speed

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

func _physics_process(delta: float) -> void:
	if boomerang:
		_fly_time += delta
		if not _returning and _fly_time >= BOOMERANG_OUT_TIME:
			_start_return()
		if _returning:
			var player := get_tree().get_first_node_in_group("player") as Node2D
			if player == null:
				queue_free()
				return
			var to_player: Vector2 = player.global_position - global_position
			if to_player.length() <= CATCH_DISTANCE:
				queue_free()   ## 回到手中
				return
			_velocity = _velocity.move_toward(to_player.normalized() * speed, BOOMERANG_RETURN_ACCEL * delta)
		else:
			_apply_homing(delta)
	else:
		_apply_homing(delta)
	_prev_position = global_position
	position += _velocity * delta
	if boomerang:
		rotation += 14.0 * delta   ## 回旋盾旋转动画
	else:
		rotation = _velocity.angle()   ## 箭/法弹朝向随飞行方向（贴图已在 _ready 转正到 +x）
	life_time -= delta
	if life_time <= 0.0:
		queue_free()

## 回旋盾进入回程：清空命中记录，回程可再打一程
func _start_return() -> void:
	if _returning:
		return
	_returning = true
	_hit_bodies.clear()

## 立刻把速度指向玩家（撞墙掉头等需要瞬时转向的场景）
func _aim_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		queue_free()
		return
	_velocity = (player.global_position - global_position).normalized() * speed

## 从上帧位置向当前速度方向做短射线，取墙面法线（取不到就原路弹回）
func _wall_normal() -> Vector2:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.new()
	q.from = _prev_position
	q.to = _prev_position + _velocity.normalized() * 40.0
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -_velocity.normalized()
	return hit["normal"]

func _apply_homing(delta: float) -> void:
	if homing_strength <= 0.0:
		return
	var target := _nearest_enemy()
	if target == null:
		return
	var desired := (target.global_position - global_position).normalized() * speed
	_velocity = _velocity.move_toward(desired, homing_strength * delta)

## homing_range 内最近的敌人（跳过本程已命中的，穿透弹径直飞过）
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := homing_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D) or not is_instance_valid(e) or e in _hit_bodies:
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	return best

func _on_body_entered(body: Node) -> void:
	if body in _hit_bodies:
		return
	if body.is_in_group("wall"):
		if boomerang:
			global_position = _prev_position   ## 回退出墙，防止嵌进墙体再穿出
			if not _returning:
				_start_return()
				_aim_at_player()   ## 去程撞墙：立刻掉头，不做渐进转向（否则会先扎进墙里）
			else:
				_velocity = _velocity.bounce(_wall_normal())   ## 回程撞墙：反弹后继续追踪玩家
		else:
			queue_free()
		return
	if body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		_hit_bodies.append(body)
		body.take_damage(damage)
		EventBus.hit_landed.emit(body, damage)
		if aoe_radius > 0.0:
			_explode(body)
		if boomerang:
			# 弹射：去程最多打 BOUNCE_MAX 个目标，弹满或没有下一个目标就返航
			if _returning:
				pass   ## 回程只顺路命中，不再改向
			elif _hit_bodies.size() >= BOUNCE_MAX:
				_start_return()
			else:
				var next := _nearest_enemy()
				if next != null:
					_velocity = (next.global_position - global_position).normalized() * speed
				else:
					_start_return()
		elif not pierce:
			queue_free()

## 范围爆发（长弓蓄力）：对半径内其他敌人造成 AOE_DAMAGE_MULT 倍伤害 + 扩散环视觉
func _explode(direct_hit: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == direct_hit or not (e is Node2D) or not is_instance_valid(e) or e in _hit_bodies:
			continue
		if (e as Node2D).global_position.distance_to(global_position) <= aoe_radius:
			if e.has_method("take_damage"):
				_hit_bodies.append(e)
				e.take_damage(damage * AOE_DAMAGE_MULT)
	var ring := Polygon2D.new()
	var pts: PackedVector2Array = []
	var segments := 20
	for i in range(segments):
		var a := float(i) / float(segments) * TAU
		pts.append(Vector2(cos(a), sin(a)) * aoe_radius)
	ring.polygon = pts
	ring.color = Color(tint.r, tint.g, tint.b, 0.45)
	ring.scale = Vector2(0.3, 0.3)
	ring.z_index = 11
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	var tw := get_tree().create_tween()
	tw.tween_property(ring, "scale", Vector2(1.0, 1.0), 0.22)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ring.queue_free)
