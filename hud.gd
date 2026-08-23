class_name Hud
extends CanvasLayer

## HUD（Phase 0b + 3）：血条（来自 main.tscn）+ 等级 / 经验 / 货币 / 祝福数。
## 额外文本标签在代码里创建，避免手改 .tscn 引入注释/格式错误。

@onready var _bar_fill: ColorRect = $HealthBar/Fill
@onready var _label: Label = $HealthBar/Label

var _lv_label: Label
var _xp_label: Label
var _coin_label: Label
var _shard_label: Label
var _boon_label: Label
var _inv_label: Label
var _weapon_label: Label

func _ready() -> void:
	_build_extra()
	# 数据走 RunState(autoload)：场景切换后无需再重新找 Player 节点，天然不丢连接
	RunState.health_changed.connect(_on_health_changed)
	RunState.stats_changed.connect(_on_stats_changed)
	RunState.inventory_changed.connect(_on_inventory_changed)
	RunState.weapon_changed.connect(_on_weapon_changed)
	if not MetaState.shards_changed.is_connected(_on_shards_changed):
		MetaState.shards_changed.connect(_on_shards_changed)
	if not BoonManager.boons_changed.is_connected(_on_boons_changed):
		BoonManager.boons_changed.connect(_on_boons_changed)
	## 键盘/手柄切换时刷新武器行与背包行的键名提示
	if not InputDevice.device_changed.is_connected(_on_device_changed):
		InputDevice.device_changed.connect(_on_device_changed)
	_update(RunState.current_health, RunState.max_health)
	_on_stats_changed(RunState.level, RunState.xp, RunState.xp_to_next, RunState.currency)
	_on_boons_changed(BoonManager.active_boons.size())
	_on_inventory_changed()
	_on_weapon_changed(RunState.weapon_idx)
	_on_shards_changed(MetaState.shards)

func _build_extra() -> void:
	_lv_label = Label.new()
	_lv_label.name = "LvLabel"
	_lv_label.position = Vector2(20.0, 48.0)
	add_child(_lv_label)
	_xp_label = Label.new()
	_xp_label.name = "XpLabel"
	_xp_label.position = Vector2(20.0, 70.0)
	add_child(_xp_label)
	_coin_label = Label.new()
	_coin_label.name = "CoinLabel"
	_coin_label.position = Vector2(20.0, 92.0)
	add_child(_coin_label)
	_shard_label = Label.new()
	_shard_label.name = "ShardLabel"
	_shard_label.position = Vector2(20.0, 114.0)
	add_child(_shard_label)
	_boon_label = Label.new()
	_boon_label.name = "BoonLabel"
	_boon_label.position = Vector2(20.0, 136.0)
	add_child(_boon_label)
	_inv_label = Label.new()
	_inv_label.name = "InvLabel"
	_inv_label.position = Vector2(20.0, 158.0)
	add_child(_inv_label)
	_weapon_label = Label.new()
	_weapon_label.name = "WeaponLabel"
	_weapon_label.position = Vector2(20.0, 180.0)
	add_child(_weapon_label)

func _on_health_changed(new_health: float, max_health: float) -> void:
	_update(new_health, max_health)

func _update(new_health: float, max_health: float) -> void:
	if max_health <= 0.0:
		return
	var ratio := clampf(new_health / max_health, 0.0, 1.0)
	_bar_fill.size.x = 200.0 * ratio
	_label.text = "HP " + str(int(new_health)) + "/" + str(int(max_health))

func _on_stats_changed(level: int, xp: float, xp_to_next: float, currency: float) -> void:
	_lv_label.text = "Lv " + str(level)
	_xp_label.text = "EXP " + str(int(xp)) + "/" + str(int(xp_to_next))
	_coin_label.text = "金币 " + str(int(currency))
	# 祝福数由 _on_boons_changed 单独维护

## 英灵碎片行（局外成长货币）：列在金币下方，跨场景总视图可见
func _on_shards_changed(total: int) -> void:
	_shard_label.text = "英灵碎片 " + str(total)

func _on_boons_changed(count: int) -> void:
	_boon_label.text = "祝福 %d/%d" % [count, BoonManager.MAX_BOONS]

## 背包行：列出所有持有消耗品及热键，空则提示
func _on_inventory_changed() -> void:
	var parts: Array[String] = []
	for id in RunState.inventory.keys():
		parts.append("%s×%d [按%s]" % [Items.item_name(id), RunState.item_count(id), Items.hotkey_label(id)])
	_inv_label.text = "背包: " + ("  ".join(parts) if not parts.is_empty() else "空") + "  [%s 打开]" % InputDevice.hint(&"ui_cancel")

func _on_weapon_changed(idx: int) -> void:
	## 键名提示用 hint() 按当前设备拼：键盘 [J 攻击｜空格 翻滚｜F 交互] ↔ 手柄 [X 攻击｜A 翻滚｜RB 交互]。武器开局选定后战斗不再切换。
	_weapon_label.text = "武器: " + String(Player.WEAPONS[idx]["name"]) + " [%s 攻击｜%s 翻滚｜%s 交互]" % [
		InputDevice.hint(&"attack"),
		InputDevice.hint(&"roll"), InputDevice.hint(&"interact"),
	]

## 键盘/手柄切换：重绘两行带键名的标签
func _on_device_changed(_gamepad: bool) -> void:
	_on_inventory_changed()
	_on_weapon_changed(RunState.weapon_idx)
