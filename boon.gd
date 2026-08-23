class_name Boon
extends Resource

## 神明祝福（机制型词缀）。数据 + 行为合一：
## 每张卡是一个独立机制（card_id 唯一），重复获得同一张卡时等级 +1、数值成长，
## 不再有 T1~T4 的"同机制数值爬梯"卡。命中时由 on_hit 施加机制效果。
## 同神/同标签协同由 BoonManager 依据已持有集合计算。

const MAX_LEVEL: int = 4

@export var boon_name: String = "未命名祝福"
@export var god: StringName = &"???"
@export var card_id: StringName = &""
@export var tags: Array[StringName] = []
@export var description: String = ""

var level: int = 1   ## 重复获得时成长（1..MAX_LEVEL），数值表见各子类 _apply_level

## 标签中文名（卡面展示用）
const TAG_LABELS: Dictionary = {
	&"thunder": "雷",
	&"tide": "潮",
	&"blood": "血",
	&"gale": "风",
	&"area": "范围",
	&"ultimate": "终极",
	&"forge": "锻造",
}

## 重复获得同一张卡时由 BoonManager.grant_boon 调用：等级 +1 并重算数值。
## 已满级返回 false（调用方应保证满级卡不再进入卡池）。
func upgrade() -> bool:
	if level >= MAX_LEVEL:
		return false
	level += 1
	_apply_level()
	return true

## 按当前 level 从数值表重算本卡数值（子类实现；工厂建卡后也调用一次）
func _apply_level() -> void:
	pass

## 玩家攻击命中 [enemy] 造成 [_damage] 时调用。
## [_scene] 为当前场景根，用于查找附近敌人与挂载视觉特效。
func on_hit(_enemy: Node, _damage: float, _scene: Node) -> void:
	pass

## 被玩家获得时调用（BoonManager.grant_boon）。
## 需要监听 EventBus 的卡在此连接信号——不要在 _init/on_hit 里连，
## 否则卡池里未持有的卡也会提前生效。升级只改数值，信号连接不受影响。
func on_granted() -> void:
	pass

## 被替换/移除时调用（BoonManager.replace_boon / reset）。在此断开 on_granted 里连的信号，
## 否则卡池实例仍持有引用、资源不释放，幽灵效果会继续生效。
func on_removed() -> void:
	pass

## 攻击伤害修正钩子：BoonManager.modify_attack_damage 对每张持有卡依次调用。
func modify_damage(base: float) -> float:
	return base

## 属性管道钩子（赫尔墨斯速度系）：对应 BoonManager.modify_xxx 管线。
func modify_move_speed(base: float) -> float:
	return base

func modify_roll_iframe(base: float) -> float:
	return base

func modify_roll_speed(base: float) -> float:
	return base

func modify_attack_duration(base: float) -> float:
	return base

## 武器变体修改钩子（赫菲斯托斯锻造系）：对当前武器字典做复制修改后返回。
## 只有武器变体卡会改写内容；其余卡原样返回。
func modify_weapon(w: Dictionary) -> Dictionary:
	return w

## 翻滚触发钩子：玩家开始翻滚时由 BoonManager.roll_triggered 调用。
func on_roll(_player: Node, _scene: Node) -> void:
	pass


# ---------- 宙斯 · 雷 ----------
## 「连锁闪电」：命中时电流向附近敌人跳跃（等级提升范围/伤害/连锁数）
class ZeusBoon extends Boon:
	const CHAIN_RANGE: Array[float] = [90.0, 110.0, 130.0, 150.0]
	const CHAIN_DAMAGE: Array[float] = [5.0, 6.0, 8.0, 12.0]
	const MAX_CHAINS: Array[int] = [3, 4, 6, 8]

	var chain_range: float = 90.0
	var chain_damage: float = 5.0
	var max_chains: int = 3

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		chain_range = CHAIN_RANGE[i]
		chain_damage = CHAIN_DAMAGE[i]
		max_chains = MAX_CHAINS[i]

	func on_hit(enemy: Node, _damage: float, scene: Node) -> void:
		if not (enemy is Node2D) or scene == null:
			return
		var origin := (enemy as Node2D).global_position
		var tree := scene.get_tree()
		if tree == null:
			return
		var chained := 0
		for other in tree.get_nodes_in_group("enemy"):
			if other == enemy or not is_instance_valid(other) or not (other is Node2D):
				continue
			if (other as Node2D).global_position.distance_to(origin) > chain_range:
				continue
			if chained >= max_chains:
				break
			_spawn_lightning(scene, origin, (other as Node2D).global_position)
			if other.has_method("take_damage"):
				other.take_damage(chain_damage)
			chained += 1

	func _spawn_lightning(scene: Node, from: Vector2, to: Vector2) -> void:
		var line := Line2D.new()
		line.points = PackedVector2Array([from, to])
		line.width = 2.0
		line.default_color = Color(0.7, 0.8, 1.0)
		line.z_index = 10
		scene.add_child(line)
		var t := Timer.new()
		t.wait_time = 0.12
		t.one_shot = true
		t.timeout.connect(line.queue_free)
		scene.add_child(t)
		t.start()

# ---------- 波塞冬 · 潮 ----------
## 两张卡共用一个类：wave_on_kill=false 为「巨浪冲击」（命中击退+爆炸），
## wave_on_kill=true 为「海神之怒」（任意击杀触发冲击波，on_hit 不生效）。
class PoseidonBoon extends Boon:
	const KB_FORCE: Array[float] = [320.0, 360.0, 420.0, 480.0]
	const EXP_RANGE: Array[float] = [70.0, 90.0, 110.0, 140.0]
	const EXP_DAMAGE: Array[float] = [8.0, 10.0, 14.0, 20.0]
	const WAVE_RANGE: Array[float] = [250.0, 275.0, 300.0, 330.0]
	const WAVE_DAMAGE: Array[float] = [15.0, 20.0, 25.0, 30.0]
	const WAVE_KB: Array[float] = [260.0, 280.0, 300.0, 320.0]

	var knockback_force: float = 0.0
	var explosion_range: float = 0.0
	var explosion_damage: float = 0.0
	var wave_on_kill: bool = false       ## 区分两张卡的机制开关
	var wave_range: float = 0.0
	var wave_damage: float = 0.0
	var wave_knockback: float = 0.0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		if wave_on_kill:
			wave_range = WAVE_RANGE[i]
			wave_damage = WAVE_DAMAGE[i]
			wave_knockback = WAVE_KB[i]
		else:
			knockback_force = KB_FORCE[i]
			explosion_range = EXP_RANGE[i]
			explosion_damage = EXP_DAMAGE[i]

	func on_granted() -> void:
		if wave_on_kill and not EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.connect(_on_enemy_died)

	func on_removed() -> void:
		if EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.disconnect(_on_enemy_died)

	func on_hit(enemy: Node, _damage: float, scene: Node) -> void:
		if not (enemy is Node2D) or scene == null:
			return
		if knockback_force <= 0.0 and explosion_damage <= 0.0:
			return   ## 「海神之怒」不走命中管道
		var center := (enemy as Node2D).global_position
		if enemy.has_method("apply_knockback"):
			var dir := Vector2.RIGHT
			var tree := scene.get_tree()
			if tree != null:
				var player := tree.get_first_node_in_group("player")
				if player != null:
					dir = (center - player.global_position).normalized()
			(enemy as Node2D).apply_knockback(dir, knockback_force)
		var t := scene.get_tree()
		if t != null:
			for other in t.get_nodes_in_group("enemy"):
				if other == enemy or not is_instance_valid(other) or not (other is Node2D):
					continue
				if (other as Node2D).global_position.distance_to(center) <= explosion_range:
					if other.has_method("take_damage"):
						other.take_damage(explosion_damage)
		_spawn_explosion(scene, center, explosion_range, Color(0.3, 0.7, 1.0, 0.5))

	## 「海神之怒」：任意敌人死亡时，以其位置为中心爆发潮水冲击波（范围伤害+击退）。
	## 允许连锁：冲击波击杀会再触发冲击波。
	func _on_enemy_died(enemy: Node) -> void:
		if not (enemy is Node2D):
			return
		var tree := (enemy as Node).get_tree()
		if tree == null:
			return
		var center := (enemy as Node2D).global_position
		for other in tree.get_nodes_in_group("enemy"):
			if other == enemy or not is_instance_valid(other) or not (other is Node2D):
				continue
			var offset := (other as Node2D).global_position - center
			if offset.length() <= wave_range:
				if other.has_method("apply_knockback"):
					other.apply_knockback(offset.normalized(), wave_knockback)
				if other.has_method("take_damage"):
					other.take_damage(wave_damage)
		var scene := tree.current_scene
		if scene != null:
			_spawn_explosion(scene, center, wave_range, Color(0.3, 0.8, 1.0, 0.45))

	func _spawn_explosion(scene: Node, at: Vector2, radius: float, color: Color) -> void:
		var ring := Polygon2D.new()
		var pts: PackedVector2Array = []
		var segments := 24
		for i in range(segments):
			var a := float(i) / float(segments) * TAU
			pts.append(Vector2(cos(a), sin(a)) * radius)
		ring.polygon = pts
		ring.position = at
		ring.color = color
		ring.scale = Vector2(0.3, 0.3)
		ring.z_index = 11
		scene.add_child(ring)
		var tw := scene.get_tree().create_tween()
		tw.tween_property(ring, "scale", Vector2(1.0, 1.0), 0.25)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.25)
		tw.tween_callback(ring.queue_free)


# ---------- 阿瑞斯 · 血 ----------
## 三张卡共用一个类，由 stat 区分：bleed=「战血沸腾」（流血 DoT）、
## lifesteal=「嗜血」（击杀流血敌人回血，需配合流血）、ramp=「血祭」（低血增伤）。
class AresBoon extends Boon:
	const BLEED_DPS: Array[float] = [4.0, 7.0, 9.0, 12.0]
	const BLEED_DURATION: Array[float] = [2.0, 3.0, 3.0, 4.0]
	const LIFESTEAL: Array[float] = [6.0, 8.0, 10.0, 12.0]
	const RAMP_MAX_BONUS: Array[float] = [0.5, 0.75, 1.0, 1.25]   ## 0 血时的最大增伤倍率

	const BLEED_NODE: StringName = &"AresBleed"

	var stat: StringName = &""       ## 本卡机制：&"bleed" / &"lifesteal" / &"ramp"
	var bleed_dps: float = 0.0
	var bleed_duration: float = 0.0
	var lifesteal: float = 0.0
	var ramp_max_bonus: float = 0.0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		match stat:
			&"bleed":
				bleed_dps = BLEED_DPS[i]
				bleed_duration = BLEED_DURATION[i]
			&"lifesteal":
				lifesteal = LIFESTEAL[i]
			&"ramp":
				ramp_max_bonus = RAMP_MAX_BONUS[i]

	func on_granted() -> void:
		if lifesteal > 0.0 and not EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.connect(_on_enemy_died)

	func on_removed() -> void:
		if EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.disconnect(_on_enemy_died)

	func on_hit(enemy: Node, _damage: float, _scene: Node) -> void:
		if bleed_dps <= 0.0:
			return   ## 嗜血/血祭不走命中管道
		if not (enemy is Node2D) or not enemy.has_method("take_damage"):
			return
		# 流血不叠加，重复命中刷新时长与伤害
		var existing := enemy.get_node_or_null(String(BLEED_NODE)) as Timer
		if existing != null:
			existing.set_meta("dps", bleed_dps)
			existing.set_meta("left", int(bleed_duration / 0.5))
			return
		var t := Timer.new()
		t.name = String(BLEED_NODE)
		t.wait_time = 0.5
		t.one_shot = false
		t.set_meta("enemy", enemy)
		t.set_meta("dps", bleed_dps)
		t.set_meta("left", int(bleed_duration / 0.5))
		t.timeout.connect(_on_bleed_tick.bind(t))
		enemy.add_child(t)
		t.start()

	func _on_bleed_tick(timer: Timer) -> void:
		var enemy: Node = timer.get_meta("enemy")
		if not is_instance_valid(enemy):
			timer.stop()
			timer.queue_free()
			return
		if enemy.has_method("take_damage"):
			## 流血 tick 跳过受击无敌帧：否则高攻速下 tick 常被 0.12s 无敌帧吞掉
			enemy.take_damage(float(timer.get_meta("dps")) * 0.5, true)
		var left: int = timer.get_meta("left")
		left -= 1
		if left <= 0:
			timer.stop()
			timer.queue_free()
		else:
			timer.set_meta("left", left)

	## 「嗜血」：敌人带着流血死亡 → 玩家回血（需持有「战血沸腾」施加流血）
	func _on_enemy_died(enemy: Node) -> void:
		if not (enemy is Node2D):
			return
		if (enemy as Node).get_node_or_null(String(BLEED_NODE)) == null:
			return
		var tree := (enemy as Node).get_tree()
		if tree == null:
			return
		var player := tree.get_first_node_in_group("player")
		if player != null and player.has_method("heal"):
			player.heal(lifesteal)
		else:
			RunState.heal(lifesteal)

	## 「血祭」：血量越低伤害越高，0 血时达到 ramp_max_bonus
	func modify_damage(base: float) -> float:
		if ramp_max_bonus <= 0.0 or RunState.max_health <= 0.0:
			return base
		var missing := 1.0 - clampf(RunState.current_health / RunState.max_health, 0.0, 1.0)
		return base * (1.0 + missing * ramp_max_bonus)

# ---------- 赫尔墨斯 · 风 ----------
## 四张卡共用一个类，由 stat 区分：move=「迅捷」、roll=「风滚」、
## haste=「疾攻」、dash=「神行」（翻滚爆发）。
class HermesBoon extends Boon:
	const MOVE_MULT: Array[float] = [1.18, 1.24, 1.30, 1.36]
	const IFRAME_MULT: Array[float] = [1.55, 1.70, 1.85, 2.00]
	const ROLL_SPD_MULT: Array[float] = [1.30, 1.40, 1.50, 1.60]
	const ATK_SPD_MULT: Array[float] = [0.70, 0.65, 0.60, 0.55]
	const BURST_DAMAGE: Array[float] = [12.0, 18.0, 24.0, 30.0]
	const BURST_RANGE: Array[float] = [60.0, 70.0, 80.0, 90.0]

	var stat: StringName = &""       ## 本卡机制：&"move" / &"roll" / &"haste" / &"dash"
	var move_mult: float = 1.0
	var roll_iframe_mult: float = 1.0
	var roll_speed_mult: float = 1.0
	var attack_speed_mult: float = 1.0
	var roll_burst_damage: float = 0.0
	var roll_burst_range: float = 60.0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		match stat:
			&"move":
				move_mult = MOVE_MULT[i]
			&"roll":
				roll_iframe_mult = IFRAME_MULT[i]
				roll_speed_mult = ROLL_SPD_MULT[i]
			&"haste":
				attack_speed_mult = ATK_SPD_MULT[i]
			&"dash":
				roll_burst_damage = BURST_DAMAGE[i]
				roll_burst_range = BURST_RANGE[i]

	func modify_move_speed(base: float) -> float:
		return base * move_mult

	func modify_roll_iframe(base: float) -> float:
		return base * roll_iframe_mult

	func modify_roll_speed(base: float) -> float:
		return base * roll_speed_mult

	func modify_attack_duration(base: float) -> float:
		return base * attack_speed_mult

	## 「神行」：翻滚起手瞬间，对周围敌人造成爆发伤害（飘字走敌人自身 take_damage）
	func on_roll(player: Node, _scene: Node) -> void:
		if roll_burst_damage <= 0.0 or not (player is Node2D):
			return
		var tree := (player as Node).get_tree()
		if tree == null:
			return
		for e in tree.get_nodes_in_group("enemy"):
			if not (e is Node2D):
				continue
			if (e as Node2D).global_position.distance_to((player as Node2D).global_position) <= roll_burst_range:
				if e.has_method("take_damage"):
					e.take_damage(roll_burst_damage)



# ---------- 宙斯 · 雷（新） ----------
## 「雷霆风暴」：每第 N 次命中在命中处降下雷击，对周围敌人造成范围伤害。
class ZeusStormBoon extends Boon:
	const STORM_EVERY: Array[int] = [4, 3, 2, 2]
	const STORM_DAMAGE: Array[float] = [10.0, 14.0, 20.0, 28.0]
	const STORM_RANGE: Array[float] = [70.0, 80.0, 95.0, 110.0]

	var storm_every: int = 4
	var storm_damage: float = 10.0
	var storm_range: float = 70.0
	var _hits: int = 0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		storm_every = STORM_EVERY[i]
		storm_damage = STORM_DAMAGE[i]
		storm_range = STORM_RANGE[i]

	func on_hit(enemy: Node, _damage: float, scene: Node) -> void:
		if not (enemy is Node2D) or scene == null:
			return
		_hits += 1
		if _hits < storm_every:
			return
		_hits = 0
		var center := (enemy as Node2D).global_position
		var tree := scene.get_tree()
		if tree == null:
			return
		for other in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(other) or not (other is Node2D):
				continue
			if (other as Node2D).global_position.distance_to(center) <= storm_range:
				if other.has_method("take_damage"):
					other.take_damage(storm_damage)
		_spawn_ring(scene, center, storm_range)

	func _spawn_ring(scene: Node, at: Vector2, radius: float) -> void:
		var ring := Polygon2D.new()
		var pts: PackedVector2Array = []
		var segments := 20
		for i in range(segments):
			var a := float(i) / float(segments) * TAU
			pts.append(Vector2(cos(a), sin(a)) * radius)
		ring.polygon = pts
		ring.position = at
		ring.color = Color(0.7, 0.8, 1.0, 0.45)
		ring.scale = Vector2(0.3, 0.3)
		ring.z_index = 11
		scene.add_child(ring)
		var tw := scene.get_tree().create_tween()
		tw.tween_property(ring, "scale", Vector2(1.0, 1.0), 0.25)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.25)
		tw.tween_callback(ring.queue_free)

## 「电光石火」：命中时概率对另一名附近敌人追加一道闪电。
class ZeusSparkBoon extends Boon:
	const SPARK_CHANCE: Array[float] = [0.25, 0.32, 0.40, 0.50]
	const SPARK_DAMAGE: Array[float] = [6.0, 8.0, 11.0, 15.0]
	const SPARK_RANGE: Array[float] = [90.0, 100.0, 120.0, 140.0]

	var spark_chance: float = 0.25
	var spark_damage: float = 6.0
	var spark_range: float = 90.0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		spark_chance = SPARK_CHANCE[i]
		spark_damage = SPARK_DAMAGE[i]
		spark_range = SPARK_RANGE[i]

	func on_hit(enemy: Node, _damage: float, scene: Node) -> void:
		if not (enemy is Node2D) or scene == null:
			return
		if randf() > spark_chance:
			return
		var origin := (enemy as Node2D).global_position
		var tree := scene.get_tree()
		if tree == null:
			return
		var target: Node2D = null
		var best := spark_range
		for other in tree.get_nodes_in_group("enemy"):
			if other == enemy or not is_instance_valid(other) or not (other is Node2D):
				continue
			var d := (other as Node2D).global_position.distance_to(origin)
			if d < best:
				best = d
				target = other as Node2D
		if target == null:
			return
		if target.has_method("take_damage"):
			target.take_damage(spark_damage)
		_spawn_lightning(scene, origin, target.global_position)

	func _spawn_lightning(scene: Node, from: Vector2, to: Vector2) -> void:
		var line := Line2D.new()
		line.points = PackedVector2Array([from, to])
		line.width = 2.0
		line.default_color = Color(0.7, 0.8, 1.0)
		line.z_index = 10
		scene.add_child(line)
		var t := Timer.new()
		t.wait_time = 0.12
		t.one_shot = true
		t.timeout.connect(line.queue_free)
		scene.add_child(t)
		t.start()


# ---------- 波塞冬 · 潮（新） ----------
## 「生命之潮」：任意击杀敌人时回复少量生命，升级提高回复量。
class PoseidonSurgeBoon extends Boon:
	const SURGE_HEAL: Array[float] = [6.0, 8.0, 10.0, 12.0]

	var surge_heal: float = 6.0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		surge_heal = SURGE_HEAL[i]

	func on_granted() -> void:
		if not EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.connect(_on_enemy_died)

	func on_removed() -> void:
		if EventBus.enemy_died.is_connected(_on_enemy_died):
			EventBus.enemy_died.disconnect(_on_enemy_died)

	func _on_enemy_died(enemy: Node) -> void:
		if enemy == null:
			return
		var player := enemy.get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("heal"):
			player.heal(surge_heal)
		else:
			RunState.heal(surge_heal)


# ---------- 赫菲斯托斯 · 锻造 ----------
## 武器变体：作用于当前武器，通过 modify_weapon 修改武器字典。
## stat: temper=「锐锋」、swift=「迅击」、split=「分裂」。
class ForgeBoon extends Boon:
	const DMG_MULT: Array[float] = [1.20, 1.35, 1.50, 1.70]
	const SPD_MULT: Array[float] = [0.80, 0.72, 0.65, 0.58]
	const KB_BONUS: Array[float] = [60.0, 90.0, 120.0, 160.0]
	const RANGE_MULT: Array[float] = [1.10, 1.15, 1.20, 1.25]
	const SPLIT_BONUS: Array[int] = [1, 1, 2, 2]

	var stat: StringName = &""
	var damage_mult: float = 1.0
	var speed_mult: float = 1.0
	var knockback_bonus: float = 0.0
	var range_mult: float = 1.0
	var split_bonus: int = 0

	func _apply_level() -> void:
		var i := clampi(level, 1, MAX_LEVEL) - 1
		match stat:
			&"temper":
				damage_mult = DMG_MULT[i]
				range_mult = RANGE_MULT[i]
			&"swift":
				speed_mult = SPD_MULT[i]
				knockback_bonus = KB_BONUS[i]
			&"split":
				split_bonus = SPLIT_BONUS[i]
				range_mult = RANGE_MULT[i]

	func modify_weapon(w: Dictionary) -> Dictionary:
		var out := w.duplicate(true)
		match stat:
			&"temper":
				out["damage"] = float(out.get("damage", 0.0)) * damage_mult
				if out.has("damage_max"):
					out["damage_max"] = float(out["damage_max"]) * damage_mult
				if out.has("radius"):
					out["radius"] = float(out["radius"]) * range_mult
			&"swift":
				if out.has("duration"):
					out["duration"] = float(out["duration"]) * speed_mult
				if out.has("cooldown"):
					out["cooldown"] = float(out["cooldown"]) * speed_mult
				out["knockback"] = float(out.get("knockback", 0.0)) + knockback_bonus
			&"split":
				out["pierce"] = true
				if out.get("ranged", false):
					out["split"] = split_bonus + 1
				elif out.has("radius"):
					out["radius"] = float(out["radius"]) * range_mult
		return out



# ---------- 工厂：16 张机制卡（卡池），重复获得即升级 ----------
const CARD_IDS: Array[StringName] = [
	&"zeus_chain", &"zeus_storm", &"zeus_spark",
	&"poseidon_wave", &"poseidon_wrath", &"poseidon_surge",
	&"ares_bleed", &"ares_lifesteal", &"ares_ramp",
	&"hermes_move", &"hermes_roll", &"hermes_haste", &"hermes_dash",
	&"forge_temper", &"forge_swift", &"forge_split",
]

static func make_boon(p_card_id: StringName) -> Boon:
	match p_card_id:
		&"zeus_chain":
			return _make_zeus_chain()
		&"poseidon_wave":
			return _make_poseidon_wave()
		&"poseidon_wrath":
			return _make_poseidon_wrath()
		&"ares_bleed":
			return _make_ares_bleed()
		&"ares_lifesteal":
			return _make_ares_lifesteal()
		&"ares_ramp":
			return _make_ares_ramp()
		&"hermes_move":
			return _make_hermes(&"move", "迅捷", [&"gale"],
				"移动速度提升（升级提高倍率）。")
		&"hermes_roll":
			return _make_hermes(&"roll", "风滚", [&"gale"],
				"翻滚更快、无敌时间延长（升级继续提高）。")
		&"hermes_haste":
			return _make_hermes(&"haste", "疾攻", [&"gale"],
				"攻击后摇缩短，法杖冷却同步缩短（升级进一步加快）。")
		&"hermes_dash":
			return _make_hermes(&"dash", "神行", [&"gale", &"ultimate"],
				"终极：翻滚瞬间对周围敌人造成风暴伤害（升级提高伤害与范围）。")

		&"zeus_storm":
			return _make_zeus_storm()

		&"zeus_spark":
			return _make_zeus_spark()

		&"poseidon_surge":
			return _make_poseidon_surge()

		&"forge_temper":
			return _make_forge(&"temper", "锐锋", "武器伤害提升、范围扩大。")

		&"forge_swift":
			return _make_forge(&"swift", "迅击", "武器攻击更快、击退更强。")

		&"forge_split":
			return _make_forge(&"split", "分裂", "远程武器额外发射投射物并贯穿；近战范围扩大。")

	return Boon.new()

static func make_all_boons() -> Array[Boon]:
	var list: Array[Boon] = []
	for id in CARD_IDS:
		list.append(make_boon(id))
	return list

static func _make_zeus_chain() -> ZeusBoon:
	var b := ZeusBoon.new()
	b.card_id = &"zeus_chain"
	b.god = &"宙斯"
	b.boon_name = "连锁闪电"
	b.tags = [&"thunder"]
	b.description = "攻击命中时电流连锁至附近敌人（升级提高范围、伤害与连锁数）。"
	b._apply_level()
	return b

static func _make_poseidon_wave() -> PoseidonBoon:
	var b := PoseidonBoon.new()
	b.card_id = &"poseidon_wave"
	b.god = &"波塞冬"
	b.boon_name = "巨浪冲击"
	b.tags = [&"tide"]
	b.description = "命中击退敌人并引发范围爆炸（升级提高击退、范围与伤害）。"
	b._apply_level()
	return b

static func _make_poseidon_wrath() -> PoseidonBoon:
	var b := PoseidonBoon.new()
	b.card_id = &"poseidon_wrath"
	b.god = &"波塞冬"
	b.boon_name = "海神之怒"
	b.tags = [&"tide", &"ultimate"]
	b.wave_on_kill = true
	b.description = "终极：任意击杀触发潮水冲击波，可连锁（升级提高范围与伤害）。"
	b._apply_level()
	return b

static func _make_ares_bleed() -> AresBoon:
	var b := AresBoon.new()
	b.card_id = &"ares_bleed"
	b.god = &"阿瑞斯"
	b.stat = &"bleed"
	b.boon_name = "战血沸腾"
	b.tags = [&"blood"]
	b.description = "命中施加流血，敌人持续掉血（升级提高伤害与持续时间）。"
	b._apply_level()
	return b

static func _make_ares_lifesteal() -> AresBoon:
	var b := AresBoon.new()
	b.card_id = &"ares_lifesteal"
	b.god = &"阿瑞斯"
	b.stat = &"lifesteal"
	b.boon_name = "嗜血"
	b.tags = [&"blood"]
	b.description = "击杀处于流血状态的敌人时回复生命（需配合「战血沸腾」；升级提高回复量）。"
	b._apply_level()
	return b

static func _make_ares_ramp() -> AresBoon:
	var b := AresBoon.new()
	b.card_id = &"ares_ramp"
	b.god = &"阿瑞斯"
	b.stat = &"ramp"
	b.boon_name = "血祭"
	b.tags = [&"blood", &"ultimate"]
	b.description = "终极：血量越低伤害越高（升级提高最大增伤幅度）。"
	b._apply_level()
	return b

static func _make_hermes(p_stat: StringName, p_name: String, p_tags: Array[StringName], p_desc: String) -> HermesBoon:
	var b := HermesBoon.new()
	b.card_id = &"hermes_" + p_stat
	b.god = &"赫尔墨斯"
	b.stat = p_stat
	b.boon_name = p_name
	b.tags = p_tags
	b.description = p_desc
	b._apply_level()
	return b

static func _make_zeus_storm() -> ZeusStormBoon:
	var b := ZeusStormBoon.new()
	b.card_id = &"zeus_storm"
	b.god = &"宙斯"
	b.boon_name = "雷霆风暴"
	b.tags = [&"thunder"]
	b.description = "每第 N 次命中引发范围雷击（升级提高频率、伤害与范围）。"
	b._apply_level()
	return b

static func _make_zeus_spark() -> ZeusSparkBoon:
	var b := ZeusSparkBoon.new()
	b.card_id = &"zeus_spark"
	b.god = &"宙斯"
	b.boon_name = "电光石火"
	b.tags = [&"thunder"]
	b.description = "命中时概率对附近另一名敌人追加闪电（升级提高概率与伤害）。"
	b._apply_level()
	return b

static func _make_poseidon_surge() -> PoseidonSurgeBoon:
	var b := PoseidonSurgeBoon.new()
	b.card_id = &"poseidon_surge"
	b.god = &"波塞冬"
	b.boon_name = "生命之潮"
	b.tags = [&"tide"]
	b.description = "任意击杀敌人时回复少量生命（升级提高回复量）。"
	b._apply_level()
	return b

static func _make_forge(p_stat: StringName, p_name: String, p_desc: String) -> ForgeBoon:
	var b := ForgeBoon.new()
	b.card_id = &"forge_" + p_stat
	b.god = &"赫菲斯托斯"
	b.stat = p_stat
	b.boon_name = p_name
	b.tags = [&"forge"]
	b.description = p_desc + "（作用于当前武器）"
	b._apply_level()
	return b
