extends Node

## 音效管理（autoload）：事件名 -> 变体文件数组，16 路 AudioStreamPlayer 池轮询播放。
## 风格约定（见 assets/audio/ATTRIBUTION.md）：战斗事件用写实系（Kenney + freesound _f），
## UI/奖励事件用 8-bit 系（retro）；同一事件不混风格。
## 延迟敏感事件已全部 WAV 化（OGG/MP3 解码有启动延迟，抽到 OGG 会慢半拍，WAV 即解即播）。
## 音量基准：UI/奖励 0dB，hit/swing -4dB（EVENT_DB），coin 在挂载点再压 -8dB（掉币频繁）——后续可按听感微调。

const POOL_SIZE := 16

## 事件映射表：事件名 -> res:// 路径数组（_ready 里统一 load，失败的跳过并 push_warning）
const EVENTS: Dictionary = {
	&"swing": [
		"res://assets/audio/combat/slash1.wav",
		"res://assets/audio/combat/slash2.wav",
		"res://assets/audio/combat/swing_f1.wav",
		"res://assets/audio/combat/swing_f2.wav",
		"res://assets/audio/combat/swing_f3.wav",
	],
	&"hit": [
		"res://assets/audio/combat/hit1.wav",
		"res://assets/audio/combat/hit2.wav",
		"res://assets/audio/combat/hit3.wav",
		"res://assets/audio/combat/hit_f1.wav",
		"res://assets/audio/combat/hit_f2.wav",
	],
	## 只用 freesound 人声哼声：与 hit 的打击冲击声拉开辨识度；
	## hurt1/2.ogg（Kenney 冲击声）因与 hit 听感雷同被移出变体池（文件保留在磁盘）
	&"hurt": [
		"res://assets/audio/combat/hurt_f1.wav",
		"res://assets/audio/combat/hurt_f2.wav",
		"res://assets/audio/combat/hurt_f3.wav",
	],
	## 死亡音效只有 8-bit 版可用（无写实系素材），全事件表中的例外
	&"death": [
		"res://assets/audio/combat/death1.wav",
		"res://assets/audio/combat/death2.wav",
		"res://assets/audio/combat/death3.wav",
	],
	&"bow_shot": [
		"res://assets/audio/combat/bow_shot.wav",
		"res://assets/audio/combat/bow_shot_f1.wav",
		"res://assets/audio/combat/bow_shot_f2.wav",
	],
	&"shield_bash": [
		"res://assets/audio/combat/shield_bash1.wav",
		"res://assets/audio/combat/shield_bash2.wav",
		"res://assets/audio/combat/shield_bash3.wav",
		"res://assets/audio/combat/shield_bash_f1.wav",
		"res://assets/audio/combat/shield_bash_f2.wav",
		"res://assets/audio/combat/shield_bash_f3.wav",
	],
	## dash_f2 长布料录音已取能量最高的 0.5s 段转 WAV，加回变体池
	&"dash": [
		"res://assets/audio/movement/dash_f1.wav",
		"res://assets/audio/movement/dash_f2.wav",
		"res://assets/audio/movement/dash1.wav",
		"res://assets/audio/movement/dash2.wav",
		"res://assets/audio/movement/dash3.wav",
	],
	&"confirm": [
		"res://assets/audio/ui/confirm3.wav",
	],
	## 错误提示音只有 Kenney 版（无 8-bit 素材），UI 事件中的例外
	&"error": [
		"res://assets/audio/ui/error1.wav",
	],
	&"coin": [
		"res://assets/audio/reward/coin3.wav",
		"res://assets/audio/reward/coin4.wav",
	],
	&"powerup": [
		"res://assets/audio/reward/powerup3.wav",
		"res://assets/audio/reward/powerup4.wav",
		"res://assets/audio/reward/powerup5.wav",
	],
	&"achievement": [
		"res://assets/audio/reward/achievement3.wav",
		"res://assets/audio/reward/achievement4.wav",
		"res://assets/audio/reward/achievement5.wav",
	],
}

## 事件音量基准（dB）：打击类略低，防止盖过 UI/奖励提示音
const EVENT_DB: Dictionary = {
	&"hit": -4.0,
	&"swing": -4.0,
}

## 高频事件加随机音调（0.95~1.05）防重复感
const PITCH_JITTER: Array[StringName] = [&"hit", &"swing", &"coin"]

## 每事件最小播放间隔（秒）：一次挥砍命中多个敌人会连发 N 次 hit，间隔内直接丢弃，
## 只保留第一声，防止"一刀响三下"；掉币同理。数值按听感在此调整。
const EVENT_MIN_INTERVAL: Dictionary = {
	&"hit": 0.06,
	&"coin": 0.08,
	&"swing": 0.05,
}

var _streams: Dictionary = {}            ## StringName -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _rr: int = 0                         ## 轮询指针（池全忙时指向最旧的播放器）
var _last_variant: Dictionary = {}       ## StringName -> 上次播放的变体下标（防连续重复）
var _last_play_tick: Dictionary = {}     ## StringName -> 上次播放的 Time.get_ticks_msec()（debounce）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   ## 暂停（选卡/商店/死亡面板）时 UI 音效仍要能响
	_load_all()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	## 战斗事件走信号集中挂载：enemy/掉落逻辑不感知音频与打击感系统，
	## 新增/替换音效只改这里，不动战斗代码
	EventBus.hit_landed.connect(_on_hit_landed)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.currency_gained.connect(_on_currency_gained)

func _load_all() -> void:
	for event in EVENTS:
		var list: Array[AudioStream] = []
		for path in EVENTS[event]:
			var s := load(path)
			if s is AudioStream:
				list.append(s)
			else:
				push_warning("AudioManager: 加载失败已跳过 " + path)
		_streams[event] = list

## 播放事件音效（随机选变体）。[param volume_db] 为事件基准之上的附加调整。
## 事件不存在或变体全加载失败时静默返回（调用点不需要判空）。
## 防连续重复：变体数 >1 时与上次下标相同则重抽（最多 3 次，防极端情况下死循环）。
## debounce：EVENT_MIN_INTERVAL 内的事件距上次播放不足间隔则丢弃本次（防"一刀响三下"）。
func play(event: StringName, volume_db: float = 0.0) -> void:
	var list: Array = _streams.get(event, [])
	if list.is_empty():
		return
	var min_interval: float = EVENT_MIN_INTERVAL.get(event, 0.0)
	if min_interval > 0.0:
		var now := Time.get_ticks_msec()
		if now - int(_last_play_tick.get(event, -1000000)) < int(min_interval * 1000.0):
			return
		_last_play_tick[event] = now
	var last: int = _last_variant.get(event, -1)
	var idx := randi() % list.size()
	if list.size() > 1:
		var retry := 0
		while idx == last and retry < 3:
			idx = randi() % list.size()
			retry += 1
	_last_variant[event] = idx
	var player := _find_player()
	player.stream = list[idx]
	player.volume_db = float(EVENT_DB.get(event, 0.0)) + volume_db
	player.pitch_scale = randf_range(0.95, 1.05) if event in PITCH_JITTER else 1.0
	player.play()

## 找空闲播放器；全忙则复用轮询指针处的（最旧的）一个
func _find_player() -> AudioStreamPlayer:
	for i in range(POOL_SIZE):
		var idx := (_rr + i) % POOL_SIZE
		if not _pool[idx].playing:
			_rr = (idx + 1) % POOL_SIZE
			return _pool[idx]
	var p := _pool[_rr]
	_rr = (_rr + 1) % POOL_SIZE
	return p

## 命中（玩家攻击打到敌人/Boss）：命中音 + 顿帧
func _on_hit_landed(_enemy: Node, _damage: float) -> void:
	play(&"hit")
	Juice.hitstop()

## 敌人死亡：死亡音 + 轻震屏
func _on_enemy_died(_enemy: Node) -> void:
	play(&"death")
	Juice.shake(3.0)

## 掉币非常频繁：音量压低 8dB
func _on_currency_gained(_amount: float) -> void:
	play(&"coin", -8.0)
