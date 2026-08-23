extends Node

## 暂停守卫（autoload）：引用计数式暂停管理。
## 之前 BoonSelectUI / ShopUI / DeathUI 各自直接读写 get_tree().paused，
## 两个界面同时打开时，先关闭的那个会把游戏恢复，另一个界面还开着游戏却在跑。
## 现在：每个界面用各自的 token acquire/release，全部释放后才真正恢复。

var _holders: Dictionary = {}   ## token(StringName) -> true

func acquire(token: StringName) -> void:
	_holders[token] = true
	get_tree().paused = true

func release(token: StringName) -> void:
	_holders.erase(token)
	if _holders.is_empty():
		get_tree().paused = false
