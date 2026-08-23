extends Node

const BoonClass = preload("res://boon.gd")

## 当前 run 激活的祝福管理（autoload：run 内跨场景持久）。
## 监听 EventBus.hit_landed，把每个激活 boon 的 on_hit 跑一遍。
## 祝福是机制型词缀，这里不写具体机制，只负责分发。

var active_boons: Array[BoonClass] = []

## 已持有统计（供抽卡偏好与卡面联动提示）：神名 -> 数量、标签 -> 数量
var owned_by_god: Dictionary[StringName, int] = {}
var owned_tags: Dictionary[StringName, int] = {}

## 激活祝福数量变化（HUD 监听显示）
signal boons_changed(count: int)

## 赐福格子上限。卡池共 16 张机制卡（Boon.CARD_IDS），每张只占 1 格，
## 满 10 格 = 本局携带上限（不是全图鉴），之后获得一律是升级；替换流程（InventoryUI.open_replace）仅作兜底。
const MAX_BOONS: int = 10

func is_full() -> bool:
	return active_boons.size() >= MAX_BOONS

## 按 card_id 查已持有的卡（未持有返回 null）。升级与替换流程都用它判重。
func find_owned(p_card_id: StringName) -> Boon:
	for x in active_boons:
		if x.card_id == p_card_id:
			return x
	return null

## 用 new_boon 替换掉 old_boon：移除旧卡（断信号、扣统计）后授予新卡。
## 若新卡已持有，则移除旧卡后给持有的那张升级——不产生重复卡。
func replace_boon(old: Boon, new_boon: Boon) -> void:
	if old == null or not active_boons.has(old):
		return
	active_boons.erase(old)
	owned_by_god[old.god] = maxi(owned_by_god.get(old.god, 1) - 1, 0)
	for t in old.tags:
		owned_tags[t] = maxi(owned_tags.get(t, 1) - 1, 0)
	old.on_removed()
	if new_boon != null:
		grant_boon(new_boon)
	else:
		boons_changed.emit(active_boons.size())

func _ready() -> void:
	if not EventBus.hit_landed.is_connected(_on_hit_landed):
		EventBus.hit_landed.connect(_on_hit_landed)

## 给予一个祝福：已持有同 card_id 的卡则升级它（数值成长，不占新格）；
## 否则入列并累计按神/标签的持有计数。
func grant_boon(b: Boon) -> void:
	if b == null:
		return
	var existing := find_owned(b.card_id)
	if existing != null:
		existing.upgrade()
		boons_changed.emit(active_boons.size())
		return
	active_boons.append(b)
	owned_by_god[b.god] = owned_by_god.get(b.god, 0) + 1
	for t in b.tags:
		owned_tags[t] = owned_tags.get(t, 0) + 1
	b.on_granted()
	boons_changed.emit(active_boons.size())

## 攻击伤害修正管线：对每张持有卡依次调用 modify_damage（血祭等增伤卡在此生效）
func modify_attack_damage(base: float) -> float:
	var dmg := base
	for b in active_boons:
		dmg = b.modify_damage(dmg)
	return dmg

## 属性管道（赫尔墨斯速度系）：逐卡叠乘
func modify_move_speed(base: float) -> float:
	for b in active_boons:
		base = b.modify_move_speed(base)
	return base

func modify_roll_iframe(base: float) -> float:
	for b in active_boons:
		base = b.modify_roll_iframe(base)
	return base

func modify_roll_speed(base: float) -> float:
	for b in active_boons:
		base = b.modify_roll_speed(base)
	return base

func modify_attack_duration(base: float) -> float:
	for b in active_boons:
		base = b.modify_attack_duration(base)
	return base

## 武器变体修改管线（赫菲斯托斯锻造系）：逐张武器变体卡对武器字典做叠加修改。
func modify_weapon(w: Dictionary) -> Dictionary:
	var out := w
	for b in active_boons:
		out = b.modify_weapon(out)
	return out

## 玩家开始翻滚时由 Player 调用（赫尔墨斯 T4 神行爆发在此生效）
func roll_triggered(player: Node, scene: Node) -> void:
	for b in active_boons:
		b.on_roll(player, scene)

## 死亡重开：清空本局所有祝福与持有统计（DeathUI 调用）
## 清空前必须逐卡走 on_removed()：断掉 on_granted 里连到 EventBus 的信号
## （海神之怒/嗜血等），否则 EventBus 永存导致幽灵效果跨局生效且逐局叠加。
func reset() -> void:
	for b in active_boons:
		b.on_removed()
	active_boons.clear()
	owned_by_god.clear()
	owned_tags.clear()
	boons_changed.emit(0)

func _on_hit_landed(enemy: Node, damage: float) -> void:
	var scene := get_tree().current_scene
	for b in active_boons:
		b.on_hit(enemy, damage, scene)
