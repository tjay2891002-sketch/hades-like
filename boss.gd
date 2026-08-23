class_name Boss
extends CharacterBody2D

## 独立 Boss 关的 Boss（Phase 4 增强）：高血量、追击玩家、接触伤害，
## 并随血量进入 3 个阶段，逐阶段解锁弹幕式攻击（瞄准飞镖 / 环形齐射 / 旋转螺旋）
## 与长距离大范围预警圈。被击败后返回主流程（main.tscn）。

const ProjectileScript = preload("res://boss_projectile.gd")
const AoeScript = preload("res://boss_aoe.gd")

@export var max_health: float = 300.0
@export var move_speed: float = 90.0
@export var contact_damage: float = 20.0

var _current_health: float = 300.0
var _sprite: AnimatedSprite2D
var _current_anim: StringName = &""   ## 当前动画名：避免每帧 play() 重置动画
var _face_left: bool = false          ## 素材朝右，左移时 flip_h

## 帧动画目录（Calciumtrice Animated Minotaur，CC-BY 3.0；48×48 帧已居中贴到 64×64 画布）
const ANIM_DIR := "res://assets/sprites/anim/"
## 按 boss_meta.txt：idle/run/attack 各 4 帧；建议帧率 idle 5、run 8、attack 8
const ANIM_SPEC: Dictionary = {
	"idle": {"frames": 4, "fps": 5.0, "loop": true},
	"run": {"frames": 4, "fps": 8.0, "loop": true},
	"attack": {"frames": 4, "fps": 8.0, "loop": true},
}
var _knockback: Vector2 = Vector2.ZERO
var _hitbox: Area2D
var _contact_cooldown: float = 0.0   ## 接触伤害冷却（配合玩家自身 0.5s 受击无敌）
var _hit_flash: float = 0.0          ## 受击闪红计时（替代 await 协程，规避对象释放后恢复崩溃）
var _died: bool = false              ## 死亡标记：防多伤害源同帧重复触发 _die（卡退根因）

var _phase: int = 1
var _attack_timer: float = 1.0
var _spiral_timer: float = 0.0
var _spiral_angle: float = 0.0

var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _hp_label: Label

func _ready() -> void:
	_current_health = max_health
	add_to_group("enemy")   ## 让连锁闪电/寻敌投射物/神行等对 Boss 生效（Boss 房无 RoomDirector，不影响清房计数）
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_build_sprite_frames()

	var cshape := RectangleShape2D.new()
	cshape.size = Vector2(60.0, 60.0)
	var ccol := CollisionShape2D.new()
	ccol.shape = cshape
	add_child(ccol)

	var hit := Area2D.new()
	hit.name = "Hitbox"
	var hshape := RectangleShape2D.new()
	hshape.size = Vector2(72.0, 72.0)
	var hcol := CollisionShape2D.new()
	hcol.shape = hshape
	hit.add_child(hcol)
	add_child(hit)
	_hitbox = hit
	# 接触伤害不走 body_entered（只触发一次），改由 _physics_process 持续判定

	_build_hp_bar()

## 代码构建 SpriteFrames：从 anim/ 目录取 boss_idle/run/attack 帧序列（米诺陶，已贴 64×64 画布）
func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for action in ANIM_SPEC:
		var spec: Dictionary = ANIM_SPEC[action]
		var anim := StringName(action)
		frames.add_animation(anim)
		frames.set_animation_speed(anim, spec["fps"])
		frames.set_animation_loop(anim, spec["loop"])
		for i in range(spec["frames"]):
			var tex := load(ANIM_DIR + "boss_" + action + "_" + str(i) + ".png") as Texture2D
			if tex != null:
				frames.add_frame(anim, tex)
	_sprite.sprite_frames = frames
	_update_animation()

## 状态驱动动画：移动→run、静止→idle；朝向按水平速度 flip_h（素材朝右）
func _update_animation() -> void:
	if _sprite == null:
		return
	if absf(velocity.x) > 1.0:
		_face_left = velocity.x < 0.0
	_sprite.flip_h = _face_left
	var anim: StringName = &"run" if velocity.length() > 1.0 else &"idle"
	if anim != _current_anim:
		_current_anim = anim
		_sprite.play(anim)

func _build_hp_bar() -> void:
	_hp_bg = ColorRect.new()
	_hp_bg.name = "HpBg"
	_hp_bg.size = Vector2(120.0, 12.0)
	_hp_bg.position = Vector2(-60.0, -52.0)
	_hp_bg.color = Color(0.15, 0.05, 0.15, 0.9)
	add_child(_hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.name = "HpFill"
	_hp_fill.size = Vector2(120.0, 12.0)
	_hp_fill.position = Vector2(-60.0, -52.0)
	_hp_fill.color = Color(0.8, 0.2, 0.9, 1.0)
	add_child(_hp_fill)
	_hp_label = Label.new()
	_hp_label.name = "HpLabel"
	_hp_label.text = "BOSS"
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.position = Vector2(-60.0, -70.0)
	_hp_label.size = Vector2(120.0, 16.0)
	add_child(_hp_label)

func _physics_process(delta: float) -> void:
	if _died:
		return
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0 and is_instance_valid(_sprite):
			_sprite.modulate = Color(1.0, 1.0, 1.0)   ## 受击闪红结束恢复常态
	_update_phase()
	_move(delta)
	_attack(delta)
	_contact_damage_tick(delta)
	_update_hp_bar()
	_update_animation()

## 接触伤害：持续重叠判定 + 冷却（修复：body_entered 只触发一次，贴脸不再掉血）
func _contact_damage_tick(delta: float) -> void:
	if _contact_cooldown > 0.0:
		_contact_cooldown -= delta
		return
	for b in _hitbox.get_overlapping_bodies():
		if b != self and b.has_method("take_damage"):
			b.take_damage(contact_damage)
			_contact_cooldown = 0.8
			break

func _update_phase() -> void:
	var ratio := _current_health / max_health
	var new_phase := 1
	if ratio <= 0.33:
		new_phase = 3
	elif ratio <= 0.66:
		new_phase = 2
	if new_phase != _phase:
		_phase = new_phase
		_spiral_angle = 0.0
		# 进入新阶段的瞬间放一发齐射，给玩家“换阶段”的明确信号
		_radial_burst(12)

func _move(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and _knockback == Vector2.ZERO:
		var dir := (player.global_position - global_position).normalized()
		velocity = dir * move_speed
	else:
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 400.0 * delta)
	move_and_slide()

func _attack(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = _main_cooldown()
		_main_attack()
	# 阶段 2/3 叠加旋转螺旋弹（0.26s 间隔：翻滚冷却标定后的可持续走位密度）
	if _phase >= 2:
		_spiral_timer -= delta
		if _spiral_timer <= 0.0:
			_spiral_timer = 0.26
			_spiral_shot()

## 弹幕密度按"翻滚有 0.8s 冷却"重新标定：玩家无敌窗口有限，
## P2/P3 以走位为主、翻滚救急，密度高于此会无解。
func _main_cooldown() -> float:
	match _phase:
		1: return 1.5
		2: return 1.4
		_: return 1.2

func _main_attack() -> void:
	match _phase:
		1: _aimed_shot()
		2: _radial_burst(14)
		_:
			_radial_burst(14)
			_spawn_aoe()

func _aimed_shot() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	_fire((player.global_position - global_position).normalized(), 12.0)

func _radial_burst(n: int) -> void:
	for i in range(n):
		var ang := TAU * float(i) / float(n)
		_fire(Vector2(cos(ang), sin(ang)), 12.0)

func _spiral_shot() -> void:
	for k in range(3):
		var ang := _spiral_angle + TAU * float(k) / 3.0
		_fire(Vector2(cos(ang), sin(ang)), 10.0)
	_spiral_angle += 0.45

## 在玩家当前位置放一个长距离大范围预警圈
func _spawn_aoe() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var aoe := AoeScript.new()
	aoe.center = player.global_position
	aoe.radius = 130.0
	aoe.damage = 28.0
	aoe.telegraph_time = 0.9
	get_tree().current_scene.add_child(aoe)

func _fire(dir: Vector2, dmg: float) -> void:
	var p := ProjectileScript.new()
	p.damage = dmg
	p.global_position = global_position
	p.launch(dir)
	get_tree().current_scene.add_child(p)

## [param _bypass_iframe] 仅为保持与 Enemy.take_damage 接口一致（阿瑞斯流血 tick 以 2 参数调用）；
## Boss 没有受击无敌帧，参数忽略不用。
func take_damage(amount: float, _bypass_iframe: bool = false) -> void:
	if _died:
		return
	_current_health = maxf(_current_health - amount, 0.0)
	_hit_flash = 0.08
	if _sprite != null:
		_sprite.modulate = Color(1.0, 0.3, 0.3)   ## 受击闪红
	if _current_health <= 0.0:
		_died = true
		call_deferred("_die")

## 供波塞冬等祝福施加击退
func apply_knockback(dir: Vector2, force: float) -> void:
	_knockback = dir * force

func _update_hp_bar() -> void:
	if _hp_fill == null:
		return
	var ratio := clampf(_current_health / max_health, 0.0, 1.0)
	_hp_fill.size.x = 120.0 * ratio
	# 血条数字：血量实时变化，避免标签永远只显示写死的 "BOSS"
	if _hp_label != null:
		_hp_label.text = "BOSS %d/%d" % [ceili(_current_health), int(max_health)]

func _die() -> void:
	var tree := get_tree()
	if tree == null:
		return   ## 已被释放（极端时序兜底）
	# 击杀奖励：经验 + 金币 + 回满血 + 消耗品入包，并标记回到主场景后弹一次赐福选择
	RunState.boss_kills += 1   ## 局外成长死亡结算计入
	EventBus.xp_gained.emit(50.0)
	EventBus.currency_gained.emit(30.0)
	RunState.heal(RunState.max_health)
	RunState.add_item(&"potion", 1)
	RunState.add_item(&"greater_potion", 1)
	preload("res://fx/floating_text.gd").spawn(tree.current_scene, global_position + Vector2(0.0, -50.0), "+血瓶 +大血瓶", Color(1.0, 0.7, 0.5))
	RunState.pending_boon_offer = true
	# 清掉残余弹幕/AoE，打开唯一出口——节奏交给玩家，不再直接切场景
	for p in tree.get_nodes_in_group("boss_projectile"):
		p.queue_free()
	for a in tree.get_nodes_in_group("boss_aoe"):
		a.queue_free()
	for e in tree.get_nodes_in_group("boss_exit"):
		if e.has_method("open_exit"):
			e.open_exit()
	queue_free()
