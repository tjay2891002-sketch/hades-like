class_name Enemy
extends CharacterBody2D

## 敌人（Phase 1 + 种类扩展）：追击 + 预警(Telegraph) + 攻击 + 受击闪白/飘字 + 归零消失
## 四种敌型（kind，外观由 Calciumtrice 帧动画区分，见 KIND_ANIM_PREFIX）：
## - CHASER 追击者（哥布林）：近战追击，现有行为
## - CHARGER 冲锋怪（史莱姆）：中距离蓄力后高速突进
## - SHOOTER 射手（法师）：保持距离放冷枪
## - TANK  坦克（盔甲锤哥布林，大块）：慢速高血高伤
## 攻击给玩家反应窗口（预警期间站定蓄力，可翻滚躲或走位拉开），是公平遭遇战的基础
@export var max_health: float = 30.0
@export var move_speed: float = 70.0
@export var attack_range: float = 40.0
@export var is_elite: bool = false  ## 精英怪：血厚/伤害高/紫色放大，房间系统按精英房生成
@export var attack_damage: float = 12.0
@export var telegraph_duration: float = 0.5
@export var recover_duration: float = 0.9
@export var xp_drop: float = 5.0          ## 击杀掉落经验
@export var currency_drop: float = 2.0     ## 击杀掉落货币
@export var kind: int = Kind.CHASER        ## 敌型
## 贴脸停止距离：近战敌型（追击者/坦克）追到此距离即停步转入攻击预警流程，
## 不再往玩家身体里怼——配合玩家翻滚穿怪（翻滚时玩家 mask=1），被围在墙角也能翻滚脱出
@export var stop_distance: float = 26.0

enum Kind { CHASER, CHARGER, SHOOTER, TANK }
enum State { CHASE, TELEGRAPH, RECOVER, DASH }

## 敌型 -> 帧动画前缀（assets/sprites/anim/full/，Calciumtrice 帧序列，每动作 10 帧，均朝右，左转 flip_h）。
## 下标与 Kind 枚举一致：chaser=小刀哥布林、charger=史莱姆、shooter=法师、tank=盔甲锤哥布林（重装变体）
const KIND_ANIM_PREFIX: Array[String] = ["goblin", "slime", "mage", "goblinhammer"]
## 敌型 -> [idle_fps, run_fps, attack_fps]（按各 *_meta.txt 建议值；death 固定 25fps 约 0.4s 播完）
const KIND_ANIM_FPS: Array[Vector3] = [
	Vector3(6.0, 10.0, 10.0),   ## goblin
	Vector3(6.0, 8.0, 10.0),    ## slime
	Vector3(6.0, 10.0, 8.0),    ## mage
	Vector3(5.0, 8.0, 8.0),     ## goblinhammer（重装偏慢）
]
const ANIM_DIR := "res://assets/sprites/anim/full/"
const DEATH_FPS: float = 25.0    ## 10 帧 / 25fps ≈ 0.4s，播完即释放
const DEATH_FREE_DELAY: float = 0.38

const EnemyProjectileScript = preload("res://enemy_projectile.gd")

const DASH_SPEED: float = 430.0       ## 冲锋突进速度
const DASH_TIME: float = 0.32         ## 冲锋持续时间
const CHARGER_WINDUP: float = 0.4     ## 冲锋蓄力时间
const SHOOTER_KEEP_MIN: float = 150.0 ## 射手保持距离下限（近于此距离后撤）
const SHOOTER_KEEP_MAX: float = 260.0 ## 射手接近上限（远于此距离逼近）
const SHOOTER_FIRE_CD: float = 1.6    ## 射手开火冷却
const SHOOTER_MAX_RANGE: float = 320.0 ## 射手飞弹有效射程（超过即消散，避免跨房间对射）

var _current_health: float = 30.0
var _sprite: AnimatedSprite2D
## 常态 modulate：普通怪白色；精英怪紫色染色区分（精英无独立动画帧，同帧 + 染色 + 放大）
var _base_color: Color = Color(1.0, 1.0, 1.0)
var _hit_iframe: float = 0.0
var _hit_flash: float = 0.0
var _state: int = State.CHASE
var _state_timer: float = 0.0
var _attack_indicator: Polygon2D  ## 攻击范围可视化（预警阶段显示），与实际圆形判定一致
var _attack_indicator_ring: Line2D ## 预警范围外圈：亮色描边，让"边界"比纯色块更清晰
var _knockback: Vector2 = Vector2.ZERO  ## 击退速度（波塞冬祝福施加），衰减后恢复 AI
var _dash_dir: Vector2 = Vector2.ZERO
var _dash_hit: bool = false
var _fire_cd: float = 1.0
var _dying: bool = false              ## 死亡动画播放中：停 AI、关碰撞、不再受击，播完才释放
var _current_anim: StringName = &""   ## 当前动画名：避免每帧 play() 重置动画
var _face_left: bool = false          ## 朝向缓存：素材均朝右，朝左时 flip_h（静止时保持上一朝向）

func _ready() -> void:
	add_to_group("enemy")
	## 碰撞分层：敌人在层 2、只撞层 1（墙+玩家+Boss）。敌人之间不做物理碰撞，
	## 怪群散开靠 _separation() 的代码分离力，不依赖层
	collision_layer = 2
	collision_mask = 1
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

	# 敌型数值（先于精英倍率应用，精英化对所有敌型生效）；外观区分已由贴图承担
	match kind:
		Kind.CHARGER:
			max_health = 18.0
			move_speed = 95.0
			attack_damage = 14.0
			xp_drop = 6.0
		Kind.SHOOTER:
			max_health = 16.0
			move_speed = 60.0
			attack_damage = 8.0
			xp_drop = 6.0
		Kind.TANK:
			max_health = 60.0
			move_speed = 40.0
			attack_damage = 18.0
			attack_range = 48.0
			xp_drop = 8.0
			currency_drop = 4.0
			scale = Vector2(1.35, 1.35)
	_current_health = max_health

	if is_elite:
		max_health *= 3.0
		_current_health = max_health
		attack_damage *= 1.5
		scale *= Vector2(1.4, 1.4)
		_base_color = Color(1.0, 0.55, 1.0)   ## 精英紫色染色：同帧动画无精英变体，染色+放大区分

	_build_sprite_frames()
	_sprite.modulate = _base_color

	# 碰撞体：让玩家攻击命中盒(Area2D)能检测到本敌人
	var cshape := RectangleShape2D.new()
	cshape.size = Vector2(28.0, 28.0)
	var ccol := CollisionShape2D.new()
	ccol.shape = cshape
	ccol.disabled = true
	add_child(ccol)
	ccol.set_deferred("disabled", false)

	# 攻击范围可视化：黄色半透明圆，与实际圆形攻击判定(attack_range)一致
	# 仅近战敌型（追击者/坦克）预警阶段显示
	_attack_indicator = Polygon2D.new()
	_attack_indicator.color = Color(1.0, 0.35, 0.25, 0.13)   ## 淡红填充：提示危险区又不糊成一坨
	_set_indicator_visible(false)
	add_child(_attack_indicator)
	var pts: PackedVector2Array = []
	var segments := 28
	for i in range(segments):
		var a := float(i) / float(segments) * TAU
		pts.append(Vector2(cos(a), sin(a)) * attack_range)
	_attack_indicator.polygon = pts
	## 外圈警示环：看清攻击边界，比纯色块直观
	_attack_indicator_ring = Line2D.new()
	_attack_indicator_ring.points = pts
	_attack_indicator_ring.closed = true
	_attack_indicator_ring.width = 2.0
	_attack_indicator_ring.default_color = Color(1.0, 0.5, 0.3, 0.8)
	_attack_indicator_ring.visible = false
	add_child(_attack_indicator_ring)

## 代码构建 SpriteFrames：按敌型前缀从 anim/full/ 取 idle/run/attack/death 帧序列（各 10 帧）。
## gesture 帧（挑衅/警戒）暂未使用，保留在磁盘备用。
func _build_sprite_frames() -> void:
	var prefix: String = KIND_ANIM_PREFIX[kind]
	var fps: Vector3 = KIND_ANIM_FPS[kind]
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var specs: Array = [
		[&"idle", fps.x, true],
		[&"run", fps.y, true],
		[&"attack", fps.z, true],
		[&"death", DEATH_FPS, false],
	]
	for spec in specs:
		var anim: StringName = spec[0]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, spec[1])
		frames.set_animation_loop(anim, spec[2])
		for i in range(10):
			var tex := load(ANIM_DIR + prefix + "_" + String(anim) + "_" + str(i) + ".png") as Texture2D
			if tex != null:
				frames.add_frame(anim, tex)
	_sprite.sprite_frames = frames
	_update_animation()

## 状态驱动动画：预警/出手→attack（预警闪烁染色照常叠加），移动（追击/冲锋突进）→run，
## 恢复/贴脸停步→idle；朝向按水平速度 flip_h（素材均朝右）。
func _update_animation() -> void:
	if absf(velocity.x) > 1.0:
		_face_left = velocity.x < 0.0
	_sprite.flip_h = _face_left
	var anim: StringName
	if _state == State.TELEGRAPH:
		anim = &"attack"
	elif velocity.length() > 1.0:
		anim = &"run"
	else:
		anim = &"idle"
	if anim != _current_anim:
		_current_anim = anim
		_sprite.play(anim)

## 预警可视化开关：同时控制填充与外圈，避免只隐藏一半
func _set_indicator_visible(v: bool) -> void:
	if is_instance_valid(_attack_indicator):
		_attack_indicator.visible = v
	if is_instance_valid(_attack_indicator_ring):
		_attack_indicator_ring.visible = v

func _physics_process(delta: float) -> void:
	if _dying:
		return   ## 死亡动画播放期间停一切 AI/计时，等定时释放
	if _hit_iframe > 0.0:
		_hit_iframe -= delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0 and is_instance_valid(_sprite):
			_sprite.modulate = _base_color

	# 击退优先：被波塞冬轰飞期间跳过 AI，纯位移并衰减
	if _knockback.length() > 1.0:
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
		move_and_slide()
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()

	match _state:
		State.CHASE:
			if is_instance_valid(_attack_indicator):
				_set_indicator_visible(false)
			match kind:
				Kind.CHARGER:
					# 中距离外逼近，进入 150 内蓄力突进
					if dist > 150.0:
						_move_toward(to_player)
					else:
						velocity = Vector2.ZERO
						_state = State.TELEGRAPH
						_state_timer = CHARGER_WINDUP
				Kind.SHOOTER:
					# 保持距离：太近后撤、太远逼近、适中就开火
					_fire_cd -= delta
					if dist < SHOOTER_KEEP_MIN:
						_move_toward(-to_player)
					elif dist > SHOOTER_KEEP_MAX:
						_move_toward(to_player)
					else:
						velocity = Vector2.ZERO
						if _fire_cd <= 0.0:
							_state = State.TELEGRAPH
							_state_timer = 0.35
				_:
					# 追击者/坦克：近战追击；贴脸（stop_distance）即停步，不再往玩家身体里怼
					if dist > stop_distance:
						_move_toward(to_player)
					else:
						velocity = Vector2.ZERO
					if dist <= attack_range:
						_state = State.TELEGRAPH
						_state_timer = telegraph_duration
						velocity = Vector2.ZERO
		State.TELEGRAPH:
			# 站定蓄力，闪烁预警，给玩家反应窗口
			velocity = Vector2.ZERO
			_state_timer -= delta
			var blink := fmod(_state_timer * 12.0, 1.0) > 0.5
			if is_instance_valid(_sprite):
				_sprite.modulate = Color(1.0, 0.9, 0.2) if blink else _base_color
			var show_indicator := (kind == Kind.CHASER or kind == Kind.TANK)
			if is_instance_valid(_attack_indicator):
				_set_indicator_visible(show_indicator)
			if _state_timer <= 0.0:
				_set_indicator_visible(false)
				match kind:
					Kind.CHARGER:
						_dash_dir = to_player.normalized()
						_dash_hit = false
						_state = State.DASH
						_state_timer = DASH_TIME
					Kind.SHOOTER:
						_fire_at(player)
						_state = State.RECOVER
						_state_timer = recover_duration
					_:
						_perform_attack(player)
						_state = State.RECOVER
						_state_timer = recover_duration
		State.DASH:
			# 冲锋突进：直线高速，撞上玩家造成一次伤害。
			# 判定距离 36 > 双方碰撞体接触距离 30（各 16+14 半径），否则撞停后永远差一点儿
			velocity = _dash_dir * DASH_SPEED
			_state_timer -= delta
			if not _dash_hit and dist <= 36.0 and player.has_method("take_damage"):
				player.take_damage(attack_damage)
				_dash_hit = true
			if _state_timer <= 0.0:
				_state = State.RECOVER
				_state_timer = 0.7
		State.RECOVER:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if is_instance_valid(_sprite):
				_sprite.modulate = _base_color
			if is_instance_valid(_attack_indicator):
				_set_indicator_visible(false)
			if _state_timer <= 0.0:
				_state = State.CHASE

	move_and_slide()
	_update_animation()

## 追击方向 + 同伴分离力，朝目标移动（分离防止怪叠成一坨、把玩家挤进墙角）
func _move_toward(to_target: Vector2) -> void:
	var dir := to_target.normalized() + _separation()
	velocity = dir.normalized() * move_speed if dir != Vector2.ZERO else Vector2.ZERO

## 射手开火：朝玩家当前位置放一枚飞弹
func _fire_at(player: Node2D) -> void:
	_fire_cd = SHOOTER_FIRE_CD
	var p := EnemyProjectileScript.new()
	p.damage = attack_damage
	p.max_range = SHOOTER_MAX_RANGE
	p.global_position = global_position
	p.launch((player.global_position - global_position).normalized())
	get_tree().current_scene.add_child(p)

## 被波塞冬祝福击退：施加一个远离来源的冲量，AI 暂时让位
func apply_knockback(dir: Vector2, force: float) -> void:
	_knockback = dir.normalized() * force

## 同伴分离力（boids separation）：44px 内按距离线性加权排斥。
## 只影响方向不增速，怪群自然散开成包围圈而不是叠成一个点。
const SEPARATION_RADIUS: float = 44.0
const SEPARATION_WEIGHT: float = 1.6
const SEPARATION_CELL: float = 64.0          ## 格子边长 ≥ 半径，3×3 邻格足以覆盖所有近邻
const SEPARATION_MAX_NEIGHBORS: int = 16     ## 单次采样上限：防极端密集时多算几帧

## 空间分桶：每物理帧只由第一个调用者重建一次格子，其余敌人只查自身 3×3 邻格；
## 避免高难度/大量敌人时每帧对整个 enemy 组 O(n²) 遍历（get_nodes_in_group 仅重建时调一次）。
static var _sep_grid: Dictionary = {}
static var _sep_frame: int = -1

func _separation() -> Vector2:
	var frame := Engine.get_physics_frames()
	if frame != _sep_frame:
		_rebuild_sep_grid()
		_sep_frame = frame
	var cell := Vector2i(floori(global_position.x / SEPARATION_CELL), floori(global_position.y / SEPARATION_CELL))
	var force := Vector2.ZERO
	var count := 0
	for gx in range(-1, 2):
		for gy in range(-1, 2):
			var bucket: Array = _sep_grid.get(cell + Vector2i(gx, gy), [])
			for other in bucket:
				if other == self or not is_instance_valid(other) or not (other is Node2D):
					continue
				var offset := global_position - (other as Node2D).global_position
				var d := offset.length()
				if d > 0.01 and d < SEPARATION_RADIUS:
					force += offset.normalized() * (1.0 - d / SEPARATION_RADIUS)
					count += 1
					if count >= SEPARATION_MAX_NEIGHBORS:
						return force * SEPARATION_WEIGHT
	return force * SEPARATION_WEIGHT

## 重建分离格子：把当前所有存活敌人按格坐标分桶（每物理帧由首个调用者执行一次）
func _rebuild_sep_grid() -> void:
	_sep_grid.clear()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var key := Vector2i(floori((e as Node2D).global_position.x / SEPARATION_CELL), floori((e as Node2D).global_position.y / SEPARATION_CELL))
		if not _sep_grid.has(key):
			_sep_grid[key] = []
		(_sep_grid[key] as Array).append(e)

func _perform_attack(player: Node2D) -> void:
	var current_dist := (player.global_position - global_position).length()
	if current_dist <= attack_range + 10.0 and player.has_method("take_damage"):
		player.take_damage(attack_damage)

## 受击。[param bypass_iframe] 为 true 时跳过受击无敌帧检查（供流血等 DoT 使用——
## DoT tick 频率低于攻速，若也吃 0.12s 无敌帧，高攻速下 tick 经常被白吞掉）
func take_damage(amount: float, bypass_iframe: bool = false) -> void:
	if _dying:
		return   ## 死亡动画播放中不再受击（避免重复触发 _die 与鞭尸飘字）
	if not bypass_iframe and _hit_iframe > 0.0:
		return
	_current_health = maxf(_current_health - amount, 0.0)
	_hit_iframe = 0.12
	_hit_flash = 0.08
	if is_instance_valid(_sprite):
		_sprite.modulate = Color(1.0, 1.0, 1.0)
	preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -22.0), "-" + str(int(amount)), Color(1.0, 1.0, 1.0))
	if _current_health <= 0.0:
		_die()

## 死亡：先发全部信号（清房计数/掉落/经验金币的时机与旧版完全一致），
## 再播死亡动画（0.38s 后释放）；期间停 AI、关碰撞、退出 enemy 组（寻敌/分离力立即忽略尸体）
func _die() -> void:
	EventBus.xp_gained.emit(xp_drop)
	EventBus.currency_gained.emit(currency_drop)
	EventBus.enemy_died.emit(self)
	_dying = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	remove_from_group("enemy")
	collision_layer = 0   ## 尸体不再挡路/被撞（碰撞形状随节点释放，无需单独处理）
	collision_mask = 0
	if is_instance_valid(_attack_indicator):
		_set_indicator_visible(false)
	_sprite.modulate = _base_color
	_current_anim = &"death"
	_sprite.play(&"death")
	get_tree().create_timer(DEATH_FREE_DELAY).timeout.connect(queue_free)
