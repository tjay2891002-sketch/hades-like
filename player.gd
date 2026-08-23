class_name Player
extends CharacterBody2D

## 顶视角 Hades-like 角色：移动 + 翻滚(i-frame) + 冲刺攻击 + 挥砍命中盒 + 血量(Phase 0b)
## 输入走 InputMap 动作（project.godot [input] 段，键盘 + 手柄双绑定）：持续状态轮询
## Input.is_action_pressed，瞬时触发走 _unhandled_input 的 event.is_action_pressed
@export var move_speed: float = 220.0
@export var roll_speed: float = 480.0
@export var roll_duration: float = 0.28
@export var roll_iframe: float = 0.22
## 翻滚冷却（从翻滚起手开始计时）：无敌帧之外的真空期是难度体系成立的前提，
## 也间接给冲刺攻击（翻滚中 J）限流。Boss 弹幕密度按此节奏标定。
@export var roll_cooldown: float = 0.8

## 武器表（Q 键轮换，当前武器存 RunState.weapon_idx 跨场景保留）。
## ranged=true 走飞弹；charge=true 为蓄力武器（按住 J 蓄力、松手释放）；
## shield_dash=true 蓄力释放为持盾冲撞（全程格挡）；throw=true 时冲刺攻击（翻滚中 J）掷出回旋盾；
## homing>0 投射物自动寻敌；伤害均过 BoonManager.modify_attack_damage。
const WEAPONS: Array[Dictionary] = [
	{"name": "短剑", "damage": 10.0, "duration": 0.18, "range": 24.0, "radius": 26.0, "ranged": false, "knockback": 0.0, "color": Color(1.0, 1.0, 0.0, 0.4)},
	{"name": "大剑", "damage": 22.0, "duration": 0.35, "range": 30.0, "radius": 42.0, "ranged": false, "knockback": 260.0, "color": Color(1.0, 0.5, 0.2, 0.45)},
	{"name": "法杖", "damage": 8.0, "duration": 0.12, "cooldown": 0.45, "ranged": true, "homing": 500.0, "color": Color(0.6, 0.8, 1.0, 0.5)},
	{"name": "长弓", "damage": 10.0, "damage_max": 32.0, "duration": 0.7, "cooldown": 0.4, "ranged": true, "charge": true, "homing": 700.0, "aoe_max": 80.0, "proj_speed": 520.0, "proj_tint": Color(0.5, 1.0, 0.6, 1.0), "color": Color(0.4, 1.0, 0.5, 0.5)},
	{"name": "坚盾", "damage": 10.0, "damage_max": 22.0, "duration": 0.35, "cooldown": 0.6, "range": 26.0, "radius": 32.0, "ranged": false, "charge": true, "shield_dash": true, "throw": true, "throw_damage": 12.0, "knockback": 340.0, "color": Color(0.7, 0.7, 0.9, 0.5)},
]
const PlayerProjectileScript = preload("res://player_projectile.gd")
const CHARGE_TIME_MAX: float = 0.7   ## 长弓满蓄时间（秒）
const DASH_ATTACK_MULT: float = 1.5  ## 冲刺攻击伤害倍率
const DASH_ATTACK_LUNGE: float = 240.0   ## 冲刺攻击前冲速度
var _ranged_cd: float = 0.0

## 血量/进度数据已全部挪入 RunState（autoload），跨场景保留。
## 本节点只保留战斗内瞬时状态（无敌帧/受击闪），读写数值一律走 RunState。

var _hit_iframe: float = 0.0  ## 受击后短无敌，避免单帧被多次扣血
var _hurt_flash: float = 0.0  ## 受击红闪计时
var _dead: bool = false       ## 死亡标记：防止 0 血后重复触发死亡逻辑

## 交互（F 键）：拾取掉落物 / 与雕像互动（Phase 3）
const INTERACT_RANGE: float = 64.0
var _interact_queued: bool = false

var _rolling: bool = false
var _roll_time: float = 0.0
var _roll_cd: float = 0.0   ## 翻滚冷却剩余时间

## 翻滚穿怪的"待恢复碰撞"状态：翻滚结束不再无条件恢复 mask=3——怪堆两三层的厚度可能
## 超过翻滚位移（~134px），定时恢复会把玩家糊回怪堆（实测问题）。此状态下保持 mask=1，
## 每帧做敌人重叠检测，确认穿出（或超时兜底）才恢复 3。
var _roll_ghost: bool = false
var _roll_ghost_time: float = 0.0
## 待恢复兜底（秒）：360° 包围下可能一直重叠，超时强制恢复 mask=3
##（此时与敌人重叠，move_and_slide 会自然滑开），防永久虚无
const ROLL_GHOST_TIMEOUT: float = 1.5
var _iframe_time: float = 0.0
var _invincible: bool = false
var _attacking: bool = false
var _attack_time: float = 0.0
var _facing: Vector2 = Vector2.RIGHT

## 攻击快照：出手瞬间定案（含祝福修正与冲刺加成），命中判定只读快照——
## 出手中途按 Q 换武器不影响本次攻击
var _attack_damage: float = 0.0
var _attack_knockback: float = 0.0
var _attack_damage_mult: float = 1.0   ## 冲刺攻击加成，出手后归 1
var _attack_lunge: float = 0.0         ## 冲刺攻击的前冲速度（出手后随攻击结束归零）

## 长弓蓄力状态
var _charging: bool = false
var _charge_time: float = 0.0
var _charge_weapon: Dictionary = {}

## 掷出的回旋盾引用：盾不在手上时禁止一切攻击（盾是实体装备）。
## 投射物接回/超时销毁后由 _shield_away() 的 is_instance_valid 检查自动解除。
var _shield_out: Node = null

func _shield_away() -> bool:
	return _shield_out != null and is_instance_valid(_shield_out)

var _hitbox: Area2D
var _hitbox_shape: CircleShape2D
var _hitbox_visual: ColorRect
var _sprite: AnimatedSprite2D
var _hit_enemies: Array[Node] = []
var _current_anim: StringName = &""   ## 当前播放的动画名：避免每帧重复 play() 重置动画

## 帧动画目录（Calciumtrice Animated Warrior，CC-BY 4.0；64×64/帧，0.5× 缩放到 32×32 显示）
const ANIM_DIR := "res://assets/sprites/anim/full/"
## 各动作帧数/帧率（按 full/ANIMATIONS.md 与 player _meta.txt：idle 12 帧 6fps、run 8 帧 10fps、attack 6 帧）
const ANIM_SPEC: Dictionary = {
	"idle": {"frames": 12, "fps": 6.0, "loop": true},
	"run": {"frames": 8, "fps": 10.0, "loop": true},
	"attack": {"frames": 6, "fps": 12.0, "loop": false},
}
## 朝向后缀：front=朝下（面向镜头）、back=朝上、left/right 侧向（素材自带左右，无需 flip_h）
const ANIM_DIRS: Array[String] = ["front", "back", "left", "right"]

func _ready() -> void:
	_sprite = $Sprite2D
	_build_sprite_frames()

	## 碰撞分层：玩家在层 1；mask=3 撞墙(1)+敌人(2)。翻滚时降为 1——只撞墙和 Boss
	##（Boss 留层 1，大体型不可穿），可穿过普通敌人（层 2）逃生，是被怪围墙角时的
	## 脱困通道；翻滚结束恢复 3（见 _start_roll 与 _physics_process 的翻滚计时）
	collision_mask = 3

	_hitbox = Area2D.new()
	_hitbox.name = "AttackHitbox"
	_hitbox.monitoring = false
	_hitbox.collision_mask = 3   ## 敌人挪到层 2 后命中盒必须含层 2（层 1 仍能打 Boss）
	_hitbox_shape = CircleShape2D.new()
	_hitbox_shape.radius = 26.0
	var col := CollisionShape2D.new()
	col.shape = _hitbox_shape
	_hitbox.add_child(col)

	# 攻击范围可视化：黄色半透明方块，攻击时显示
	_hitbox_visual = ColorRect.new()
	_hitbox_visual.size = Vector2(28.0, 28.0)
	_hitbox_visual.position = Vector2(-14.0, -14.0)
	_hitbox_visual.color = Color(1.0, 1.0, 0.0, 0.4)
	_hitbox_visual.visible = false
	_hitbox.add_child(_hitbox_visual)

	add_child(_hitbox)
	_hitbox.body_entered.connect(_on_hitbox_body_entered)

	add_to_group("player")
	call_deferred("_setup_fixed_camera")
	# 血量/经验/货币由 RunState(autoload) 自行累积与广播，这里不再连接 EventBus

## 固定视角：把跟随玩家的 Camera2D 摘下，改为固定在房间中心的镜头，人物移动不再滚动画面。
func _setup_fixed_camera() -> void:
	if not is_inside_tree():
		return
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	remove_child(cam)
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(cam)
	cam.global_position = _room_camera_center()
	cam.enabled = true
	cam.make_current()
	## 战斗/boss 房：墙贴着竞技场边界（半厚在地板外、门在墙体内）。按房间实际内容矩形自适应缩放，
	## 保证整圈墙+门在任何窗口比例下都完整显示；存档房墙在室内，保持全尺寸（zoom=1）。
	if not scene.has_method("_room_camera_center"):
		cam.zoom = _fit_camera_zoom(_combat_room_rect())

## 计算固定镜头中心：save_room 用房间中点；main 战斗用 Room 节点世界坐标；boss 竞技场以世界原点为中心。
func _room_camera_center() -> Vector2:
	var scene := get_tree().current_scene
	if scene == null:
		return global_position
	if scene.has_method("_room_camera_center"):
		return (scene as Node)._room_camera_center()
	var room := scene.get_node_or_null("Room")
	if room is Node2D:
		return (room as Node2D).global_position
	return Vector2.ZERO

## 战斗/Boss 房内容矩形（世界空间）：优先取 Room 节点上报的墙体+地板范围；
## Boss 房是静态竞技场（约 1000×580 含墙、中心为世界原点），用默认矩形兜底。
func _combat_room_rect() -> Rect2:
	var scene := get_tree().current_scene
	if scene != null:
		var room := scene.get_node_or_null("Room")
		if room != null and room.has_method("_room_camera_rect"):
			return (room as Node)._room_camera_rect()
	var c := _room_camera_center()
	return Rect2(c.x - 500.0, c.y - 290.0, 1000.0, 580.0)

## 依据房间内容矩形计算相机 zoom：把矩形完整放入视口，并留 5% 边距确保墙不被裁。
func _fit_camera_zoom(rect: Rect2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ONE
	var margin := 1.05
	var z := minf(vp.x / rect.size.x, vp.y / rect.size.y) / margin
	z = maxf(z, 0.1)
	return Vector2(z, z)


## 代码构建 SpriteFrames：从 anim/full/ 目录取 4 方向 idle/run/attack 帧序列，
## 场景里的 AnimatedSprite2D 节点只作占位，贴图全部在这里装配（NEAREST 过滤在 tscn 节点上）
func _build_sprite_frames() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for action in ANIM_SPEC:
		var spec: Dictionary = ANIM_SPEC[action]
		for dir in ANIM_DIRS:
			var anim := StringName(action + "_" + dir)
			frames.add_animation(anim)
			frames.set_animation_speed(anim, spec["fps"])
			frames.set_animation_loop(anim, spec["loop"])
			for i in range(spec["frames"]):
				var tex := load(ANIM_DIR + "player_" + action + "_" + dir + "_" + str(i) + ".png") as Texture2D
				if tex != null:
					frames.add_frame(anim, tex)
	_sprite.sprite_frames = frames
	_sprite.scale = Vector2(0.5, 0.5)   ## 原帧 64×64 → 游戏内 32×32（整数倍 NEAREST 干净）
	_update_animation()

## _facing 映射到素材朝向后缀：斜向按占优轴归并到四方向
func _facing_dir() -> String:
	if absf(_facing.x) > absf(_facing.y):
		return "right" if _facing.x > 0.0 else "left"
	return "front" if _facing.y > 0.0 else "back"

## 状态驱动动画：攻击（非蓄力）→attack；移动/翻滚→run；静止/蓄力瞄准→idle。
## 翻滚/蓄力的状态染色仍走 modulate（见 _physics_process 末尾），与动画播放互不干扰。
func _update_animation() -> void:
	var anim: StringName
	if _attacking and not _charging:
		anim = StringName("attack_" + _facing_dir())
	elif velocity.length() > 1.0:
		anim = StringName("run_" + _facing_dir())
	else:
		anim = StringName("idle_" + _facing_dir())
	## attack 不循环且时长常短于攻击判定，同方向连击时若还在播就不打断，否则重播
	if anim != _current_anim or not _sprite.is_playing():
		_current_anim = anim
		_sprite.play(anim)

# 瞬时输入触发（翻滚/攻击/交互/道具/换武器）都从这里进。
# event.is_action_pressed 默认 allow_echo=false，即原来的 not event.echo 语义。
# 持续状态（移动方向、蓄力按住）改在 _physics_process 轮询 Input.is_action_pressed——
# Input 单例全局跟踪物理按键，暂停期间也不会丢"抬起"状态，旧的事件驱动按键字典因此删除。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("roll") and not _rolling and not _attacking and _roll_cd <= 0.0:
		_start_roll()
	elif event.is_action_pressed("attack") and not _attacking and not _shield_away():
		if _rolling:
			_start_dash_attack()   ## 翻滚中按攻击 = 冲刺攻击
		else:
			_start_attack()
	elif event.is_action_pressed("interact"):
		_interact_queued = true
	elif event.is_action_pressed("item_1"):
		RunState.use_item(&"potion", self)
	elif event.is_action_pressed("item_2"):
		RunState.use_item(&"greater_potion", self)

## 暂停时清空瞬时交互队列与速度：避免选卡暂停期间排队的 F 在恢复后误触发
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_interact_queued = false
		velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if _hit_iframe > 0.0:
		_hit_iframe -= delta
	if _ranged_cd > 0.0:
		_ranged_cd -= delta
	if _roll_cd > 0.0:
		_roll_cd -= delta
	if _iframe_time > 0.0:
		_iframe_time -= delta
		if _iframe_time <= 0.0:
			_invincible = false
	if _hurt_flash > 0.0:
		_hurt_flash -= delta

	if _rolling:
		_roll_time -= delta
		if _roll_time <= 0.0:
			_begin_roll_ghost()   ## 不立即恢复碰撞：进入待恢复状态，确认穿出怪堆才恢复
		velocity = _facing * BoonManager.modify_roll_speed(roll_speed)
	elif _attacking:
		if _charging:
			# 蓄力中：原地不动，但可以按方向键调整瞄准
			velocity = Vector2.ZERO
			var aim := _read_move_dir()
			if aim != Vector2.ZERO:
				_facing = aim.normalized()
			_charge_time += delta
			# 松手或满蓄 → 释放（长弓放箭 / 坚盾冲撞）
			if not Input.is_action_pressed("attack") or _charge_time >= CHARGE_TIME_MAX:
				var ratio := clampf(_charge_time / CHARGE_TIME_MAX, 0.0, 1.0)
				var cw := _charge_weapon
				_charging = false
				if cw.get("shield_dash", false):
					_start_shield_dash(cw, ratio)   ## 冲撞阶段接管 _attacking，随计时结束
				else:
					_fire_arrow(cw, ratio)
					_attacking = false
		else:
			_attack_time -= delta
			velocity = _facing * _attack_lunge   ## 冲刺攻击前冲；普通攻击 lunge=0 即定身
			if _attack_time <= 0.0:
				_attacking = false
				_attack_lunge = 0.0
				_hitbox.monitoring = false
				_hitbox_visual.visible = false
				_hit_enemies.clear()
	else:
		var dir := _read_move_dir()
		if dir != Vector2.ZERO:
			_facing = dir.normalized()
		velocity = dir * BoonManager.modify_move_speed(move_speed)

	move_and_slide()

	## 待恢复碰撞：保持 mask=1（可从怪堆中直接走出，物理不挡），每帧确认是否已穿出；
	## 穿出或超 ROLL_GHOST_TIMEOUT 兜底才恢复 mask=3。注意这只是"无碰撞"不是"无敌"——
	## _iframe_time 照原逻辑结束，敌人攻击判定区仍能打到玩家（标准设计，勿当 bug 改）
	if _roll_ghost:
		_roll_ghost_time += delta
		if _roll_ghost_time >= ROLL_GHOST_TIMEOUT or not _overlapping_enemy():
			_roll_ghost = false
			collision_mask = 3

	# F 键交互：拾取最近的可交互物（掉落物 / 雕像）
	if _interact_queued:
		_interact_queued = false
		_try_interact()

	# 状态反馈统一管理（贴图时代改 modulate）：翻滚蓝 > 蓄力绿渐白 > 受击红 > 冷却暗橙（翻滚未就绪）> 普通白
	if _rolling:
		_sprite.modulate = Color(0.3, 0.6, 1.0)
	elif _charging:
		_sprite.modulate = Color(0.4, 1.0, 0.5).lerp(Color(1.0, 1.0, 0.9), clampf(_charge_time / CHARGE_TIME_MAX, 0.0, 1.0))
	elif _hurt_flash > 0.0:
		_sprite.modulate = Color(1.0, 0.3, 0.3)
	elif _roll_cd > 0.0:
		_sprite.modulate = Color(0.75, 0.45, 0.2)   ## 翻滚冷却中：提示冲刺攻击也不可用
	else:
		_sprite.modulate = Color(1.0, 1.0, 1.0)

	_update_animation()

## 当前移动输入方向（未归一化；无输入返回 ZERO）。
## 轮询 Input 动作状态是安全的：Input 单例全局跟踪物理按键/摇杆，暂停期间不丢"抬起"，
## 旧的事件驱动 _pressed_keys 字典（当年为防轮询状态过期）已随 InputMap 迁移删除。
func _read_move_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	return dir

func _start_roll() -> void:
	_rolling = true
	_roll_time = roll_duration
	_roll_cd = roll_cooldown
	_invincible = true
	_iframe_time = BoonManager.modify_roll_iframe(roll_iframe)
	_roll_ghost = false   ## 新翻滚清掉旧的待恢复状态（若有）
	collision_mask = 1   ## 翻滚穿怪：只撞墙和 Boss（层 1），普通敌人（层 2）可穿过逃生
	AudioManager.play(&"dash")
	# 通知祝福系统（赫尔墨斯「神行」翻滚爆发在此生效）
	BoonManager.roll_triggered(self, get_tree().current_scene)

## 翻滚结束（计时走完或被冲刺攻击取消）：进入待恢复碰撞状态，而非无条件恢复 mask=3。
## 恢复由 _physics_process 的 _roll_ghost 分支在确认穿出怪堆（或超时兜底）后执行。
func _begin_roll_ghost() -> void:
	_rolling = false
	_roll_ghost = true
	_roll_ghost_time = 0.0

## 玩家当前位置是否与敌人（层 2）重叠：用玩家自身碰撞形状做一次 intersect_shape 检测。
## Boss 在层 1 不参与——Boss 本就该阻挡玩家，翻滚也穿不过。
func _overlapping_enemy() -> bool:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or col.shape == null:
		return false   ## 取不到形状时按不重叠处理（立即恢复，行为与旧定时版一致）
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = col.shape
	params.transform = col.global_transform   ## 形状随碰撞体子节点的全局变换（含其局部偏移）
	params.collision_mask = 2   ## 只查敌人层
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()

## 冲刺攻击：翻滚中按 J——取消翻滚，伤害 ×DASH_ATTACK_MULT 并带前冲出招。
## 长弓无蓄力动作可打断，冲刺攻击 = 立即快射一箭（最小伤害 ×倍率）；
## 坚盾冲刺攻击 = 掷出回旋盾（自动寻敌，飞回手中）。
## 取当前武器（含武器变体赐福修正）：所有攻击入口统一走这里，保证变体对每把武器生效。
func _get_weapon() -> Dictionary:
	return BoonManager.modify_weapon(WEAPONS[RunState.weapon_idx])

func _start_dash_attack() -> void:
	_begin_roll_ghost()   ## 冲刺攻击取消翻滚：和计时结束走同一条待恢复路径
	_attack_damage_mult = DASH_ATTACK_MULT
	var w: Dictionary = _get_weapon()
	if w.get("throw", false):
		_throw_shield(w)
		return
	if w.get("charge", false):
		_fire_arrow(w, 0.0)
		return
	_attack_lunge = DASH_ATTACK_LUNGE
	_start_attack()

func _start_attack() -> void:
	var w: Dictionary = _get_weapon()
	if w.get("charge", false):
		_start_charge(w)
		return
	if w.get("ranged", false):
		_start_ranged_attack(w)
		return
	_attacking = true
	_attack_time = BoonManager.modify_attack_duration(w["duration"])
	# 伤害/击退在出手瞬间快照，命中判定不再回查武器表
	_attack_damage = BoonManager.modify_attack_damage(w["damage"] * _attack_damage_mult)
	_attack_knockback = float(w.get("knockback", 0.0))
	_attack_damage_mult = 1.0
	_hitbox.position = _facing * w["range"]
	_hitbox_shape.radius = w["radius"]
	_hitbox_visual.size = Vector2(w["radius"] * 1.2, w["radius"] * 1.2)
	_hitbox_visual.position = -_hitbox_visual.size * 0.5
	_hitbox_visual.color = w["color"]
	_hitbox.monitoring = true
	_hitbox_visual.visible = true
	AudioManager.play(&"swing")

## 法杖：发射飞弹（伤害在发射时修正完毕，自动寻敌），冷却期间按 J 无效
func _start_ranged_attack(w: Dictionary) -> void:
	if _ranged_cd > 0.0:
		_attack_damage_mult = 1.0   ## 冲刺加成不留给下一击
		return
	_ranged_cd = BoonManager.modify_attack_duration(w["cooldown"])
	_attacking = true
	_attack_time = BoonManager.modify_attack_duration(w["duration"])
	var dmg := BoonManager.modify_attack_damage(w["damage"] * _attack_damage_mult)
	_attack_damage_mult = 1.0
	var split := int(w.get("split", 1))
	for k in range(split):
		var p := PlayerProjectileScript.new()
		p.damage = dmg
		p.homing_strength = float(w.get("homing", 0.0))
		p.pierce = bool(w.get("pierce", false))
		get_tree().current_scene.add_child(p)   ## 先入树再设世界坐标（见 room.gd _spawn_drop_at 的顺序教训）
		p.global_position = global_position + _facing * 22.0
		var ang := _facing.angle() + (float(k) - float(split - 1) / 2.0) * 0.12
		p.launch(Vector2(cos(ang), sin(ang)))

## 长弓/坚盾：按住 J 开始蓄力（原地瞄准），松手或满蓄由 _physics_process 释放
func _start_charge(w: Dictionary) -> void:
	if _ranged_cd > 0.0:
		return
	_charging = true
	_charge_time = 0.0
	_charge_weapon = w   ## 快照武器：蓄力中途按 Q 换武器不影响这次释放
	_attacking = true
	_attack_time = CHARGE_TIME_MAX + 0.1   ## 兜底；正常由松手/满蓄结束

## 放箭：ratio=蓄力进度(0..1)，伤害在 min~max 间插值，满蓄穿透；
## 蓄力同时扩大命中范围伤害（aoe_radius 随 ratio 成长），箭矢自动寻敌
func _fire_arrow(w: Dictionary, ratio: float) -> void:
	_ranged_cd = BoonManager.modify_attack_duration(w["cooldown"])
	var dmg := BoonManager.modify_attack_damage(lerpf(w["damage"], w["damage_max"], ratio) * _attack_damage_mult)
	_attack_damage_mult = 1.0
	var split := int(w.get("split", 1))
	for k in range(split):
		var p := PlayerProjectileScript.new()
		p.damage = dmg
		p.pierce = bool(w.get("pierce", false)) or ratio >= 1.0
		p.homing_strength = float(w.get("homing", 0.0))
		p.aoe_radius = float(w.get("aoe_max", 0.0)) * ratio
		p.tint = w.get("proj_tint", Color(0.6, 0.8, 1.0, 1.0))
		p.is_arrow = true   ## 长弓投射物用箭贴图
		get_tree().current_scene.add_child(p)   ## 先入树再设世界坐标（见 room.gd _spawn_drop_at 的顺序教训）
		p.global_position = global_position + _facing * 22.0
		var ang := _facing.angle() + (float(k) - float(split - 1) / 2.0) * 0.10
		p.launch(Vector2(cos(ang), sin(ang)), float(w.get("proj_speed", 380.0)))
	AudioManager.play(&"bow_shot")

## 坚盾蓄力释放：持盾向前冲撞——伤害/位移随蓄力成长，冲撞全程格挡（无敌），强击退。
## 冲撞后进入冷却（防连冲白嫖无敌帧），疾攻可缩短该冷却。
func _start_shield_dash(w: Dictionary, ratio: float) -> void:
	_ranged_cd = BoonManager.modify_attack_duration(float(w.get("cooldown", 0.6)))
	_attack_time = lerpf(0.16, 0.28, ratio)
	_attack_lunge = lerpf(420.0, 720.0, ratio)
	_attack_damage = BoonManager.modify_attack_damage(lerpf(w["damage"], w["damage_max"], ratio))
	_attack_knockback = float(w.get("knockback", 340.0))
	_invincible = true
	_iframe_time = maxf(_iframe_time, _attack_time)   ## 冲撞全程格挡（取与翻滚无敌的较大值）
	_hitbox.position = _facing * w["range"]
	_hitbox_shape.radius = w["radius"]
	_hitbox_visual.size = Vector2(w["radius"] * 1.2, w["radius"] * 1.2)
	_hitbox_visual.position = -_hitbox_visual.size * 0.5
	_hitbox_visual.color = w["color"]
	_hitbox.monitoring = true
	_hitbox_visual.visible = true
	_hit_enemies.clear()
	AudioManager.play(&"shield_bash")

## 坚盾冲刺攻击：掷出回旋盾——自动寻敌，在最多 3 个目标间弹射，撞墙/弹满即返航。
## 盾离手期间无法攻击（J 被 _shield_away 拦截），接回或超时后恢复。
func _throw_shield(w: Dictionary) -> void:
	var dmg := BoonManager.modify_attack_damage(float(w.get("throw_damage", w["damage"])) * _attack_damage_mult)
	_attack_damage_mult = 1.0
	var p := PlayerProjectileScript.new()
	p.damage = dmg
	p.boomerang = true
	p.homing_strength = 600.0
	p.life_time = 1.6
	p.tint = Color(0.7, 0.7, 0.9, 1.0)
	p.visual_size = Vector2(26.0, 26.0)   ## 飞盾要大一号，且旋转飞行
	get_tree().current_scene.add_child(p)   ## 先入树再设世界坐标（见 room.gd _spawn_drop_at 的顺序教训）
	p.global_position = global_position + _facing * 22.0
	p.launch(_facing, 420.0)
	_shield_out = p
	AudioManager.play(&"swing")   ## 掷盾出手沿用挥砍 whoosh

func _on_hitbox_body_entered(body: Node) -> void:
	if body == self or body in _hit_enemies:
		return
	if not body.has_method("take_damage"):
		return
	if _is_blocked_by_wall(body):
		return
	_hit_enemies.append(body)
	# 伤害/击退读出手快照（_start_attack 时定案，含祝福修正与冲刺加成）
	body.take_damage(_attack_damage)
	if _attack_knockback > 0.0 and body is Node2D and body.has_method("apply_knockback"):
		(body as Node2D).apply_knockback(((body as Node2D).global_position - global_position).normalized(), _attack_knockback)
	EventBus.hit_landed.emit(body, _attack_damage)

func _is_blocked_by_wall(target: Node) -> bool:
	if not (target is Node2D):
		return false
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = (target as Node2D).global_position
	query.collision_mask = 1
	var exclude: Array[RID] = [self.get_rid()]
	if target is CollisionObject2D:
		exclude.append((target as CollisionObject2D).get_rid())
	query.exclude = exclude
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider := result["collider"] as Node
	return collider != null and collider.is_in_group("wall")

func take_damage(amount: float) -> void:
	if _dead or _invincible or _hit_iframe > 0.0:
		return
	RunState.apply_damage(amount)
	_hit_iframe = 0.5
	_hurt_flash = 0.12
	AudioManager.play(&"hurt")
	Juice.shake(6.0)   ## 玩家受击震屏强于小怪死亡（3.0）：自身安危需要更强的反馈
	preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -22.0), "-" + str(int(amount)), Color(1.0, 0.4, 0.4))
	if RunState.current_health <= 0.0:
		_die()

## 恢复生命（商店药水 / 治疗类祝福用），数据走 RunState，这里补飘字
func heal(amount: float) -> void:
	RunState.heal(amount)
	preload("res://fx/floating_text.gd").spawn(get_tree().current_scene, global_position + Vector2(0.0, -22.0), "+" + str(int(amount)), Color(0.4, 1.0, 0.6))

## 尝试花费金币。余额足够则扣除并刷新 HUD，返回 true；不足则原样返回 false
func spend_currency(amount: float) -> bool:
	return RunState.spend_currency(amount)

## 范围内最近的可交互物（group "interactable"）调用其 interact(self)
func _try_interact() -> void:
	var best: Node2D = null
	var best_dist := INTERACT_RANGE
	for node in get_tree().get_nodes_in_group("interactable"):
		if not (node is Node2D):
			continue
		var d := global_position.distance_to((node as Node2D).global_position)
		if d <= best_dist:
			best_dist = d
			best = node as Node2D
	if best != null and best.has_method("interact"):
		best.interact(self)

func _die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	RunState.player_died.emit()
