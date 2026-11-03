# astris-mouse-panning

[English](README.md) | 简体中文

为 [Astris](https://github.com/V380-Ori/Astris.Binaries)（macOS 上的 Nintendo Switch 模拟器）提供丝滑的模拟量鼠标镜头平移。

[MacRMB](https://github.com/ikoshura/MacRMB) 这类“鼠标转按键”的工具靠按住 I/J/K/L 来转动镜头，右摇杆只能收到 8 个方向上的满偏输入，所以镜头一顿一顿的。astris-mouse-panning 把鼠标速度换算成虚拟手柄右摇杆的模拟量，镜头转起来和用真手柄一样顺滑。

> [!NOTE]
> 本项目为非官方项目，与 Astris / V380-Ori 无关，不包含、不分发、也不修改 Astris 的任何文件。使用风险自负。

## 特性

- **模拟量右摇杆**：按鼠标事件时间戳把移动映射为连续的摇杆偏移，每次鼠标回报都立即发送，鼠标一停摇杆立刻归零。
- **鼠标键当手柄键**：左键、右键、中键和两个侧键都可以绑定到任意手柄按键（比如左键 → ZL，右键 → ZR）。只在平移开启时生效，关闭后点菜单不受影响。
- **Player 1 设为键盘也能用**：Astris 最常见的设置（Player 1 → Keyboard）会被透明接管：交给 `libryujinx` 的配置在内存里改写，让 Player 1 绑定到虚拟手柄；Astris 自己的设置和偏好文件原封不动。
- **键盘照常可用**：自动读取 Astris 输入设置里 Player 1 的键位并转发给虚拟手柄，在 Astris 里改键位会立即生效。
- **真手柄优先**：Player 1 在 Astris 里设为手柄、且该真实手柄已连接时，虚拟手柄自动让位，鼠标改为驱动真实手柄的右摇杆；真实手柄断开后，虚拟手柄自动恢复。
- **完全可回滚**：不修改 `Astris.app` 内的任何文件。只有通过 `run.sh` 启动的实例会被注入，像平时那样打开 Astris 就是原版。
- **无需额外权限**：所有逻辑都运行在 Astris 进程内，不需要辅助功能或输入监控权限。

## 环境要求

- Apple Silicon Mac，macOS 15 及以上
- Xcode Command Line Tools（`xcode-select --install`），用于编译
- Astris（已在 1.0.32 上验证），默认安装在 `/Applications/Astris.app`

## 快速开始

```bash
git clone https://github.com/stevenup/astris-mouse-panning.git
cd astris-mouse-panning
./run.sh                       # 首次运行会自动编译，然后启动带平移功能的 Astris
./run.sh "/path/to/game.xci"   # 同上，并在 Astris 启动后打开游戏
```

运行 `run.sh` 前请先退出 Astris（⌘Q），它不会再开第二个实例。Astris 会脱离终端在后台运行，关掉终端不影响游戏。

进入游戏后按 **⌥⌘M** 开始平移：光标消失，并听到“Tink”提示音。再按一次 ⌥⌘M 停止（“Pop”）。

拉取更新后，运行 `./build.sh` 重新编译。

## 操作

| 操作 | 方式 |
|---|---|
| 开 / 关平移 | 游戏窗口在前台时按 ⌥⌘M，或执行 `notifyutil -p dev.astrismouse.toggle` |
| 强制停止 | `notifyutil -p dev.astrismouse.stop` |
| 自动停止 | 切换到其他 App、关闭游戏窗口或停止模拟时 |
| 把运行状态写入日志 | `notifyutil -p dev.astrismouse.probe` |
| 把键位映射写入日志 | `notifyutil -p dev.astrismouse.diag` |
| 查看日志 | `tail -f ~/Library/Logs/AstrisMouse.log` |

## 配置

把 `config.env.example` 复制为 `config.env`，取消注释想修改的行。Astris 运行中也可以改：保存文件后大约半秒内生效，不用重启（日志里会出现 `config: config.env applied: fullSpeed 400.0→300.0`）。唯一的例外是 `ASTRIS_MOUSE_TAKEOVER`，只在启动时读取。

只想临时试一个值时，可以写在命令前面，例如 `ASTRIS_MOUSE_FULL_SPEED=300 ./run.sh`。`config.env` 里的值优先于命令行；从文件里删掉某一行，该项会恢复默认值。

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ASTRIS_MOUSE_FULL_SPEED` | `400` | 鼠标速度达到多少 pt/s 时摇杆满偏。越小越灵敏。 |
| `ASTRIS_MOUSE_CURVE` | `1` | 响应曲线指数。设为 1.5–2 时低速更细腻。 |
| `ASTRIS_MOUSE_SMOOTHING_MS` | `5` | 低通时间常数，只作用于运动中的速度变化；起步和停止不经过它。`0` 关闭；觉得速度忽快忽慢可以试 10–15。 |
| `ASTRIS_MOUSE_AVERAGE` | `2` | 瞬时速度 = 最近 N 次鼠标事件的位移 / 实际时间跨度。`1` 最跟手但抖，3–4 更稳但变速慢一个事件。 |
| `ASTRIS_MOUSE_HOLD_MS` | `0`（自适应） | 多久没有鼠标事件就把摇杆归零。自适应 = 鼠标回报间隔 ×1.5 + 4 ms（125 Hz 鼠标约 16 ms）。慢速移动时一顿一顿可以调到 30 左右。 |
| `ASTRIS_MOUSE_ANTI_DEADZONE` | `0.10` | 非零输出的起始幅值。与 Astris 的右摇杆死区（默认 0.1）保持一致，微小移动才能被识别。 |
| `ASTRIS_MOUSE_OUTPUT_DEADZONE` | `0.02` | 幅值低于此值时输出 0，防止漂移。 |
| `ASTRIS_MOUSE_INVERT_Y` | `0` | 反转垂直方向。 |
| `ASTRIS_MOUSE_BUTTON_LEFT` / `_RIGHT` / `_MIDDLE` / `_4` / `_5` | 不绑定 | 平移开启时按住该鼠标键所对应的手柄按键。可用名字：`a b x y minus plus home l r zl zr lstick rstick up down left right`（也认 `lt`/`rt`、`l2`/`r2`、`l3`/`r3`、`select`/`start` 等别名），`none` 表示不绑定。`_4`/`_5` 是两个侧键（后退/前进）。A/B/X/Y 按 Switch 上的标签来，自动跟随 Astris 的 *Nintendo layout* 设置。 |
| `ASTRIS_MOUSE_TOGGLE` | `cmd+alt+m` | 开关热键。修饰键：`cmd`、`alt`、`ctrl`、`shift`；按键：`a`–`z`、`0`–`9`、`f1`–`f15`、`space`、`tab`、`esc`、`return`，或直接写键码数字。 |
| `ASTRIS_MOUSE_SOUND` | `1` | 开关平移时播放提示音。 |
| `ASTRIS_MOUSE_CONTROLLER` | 自动 | 强制指定 libryujinx 的手柄句柄，一般不需要。 |
| `ASTRIS_MOUSE_TAKEOVER` | `1` | Player 1 在 Astris 里是 Keyboard（或选了手柄但没指定具体手柄）时，在内存里改写配置让 Player 1 绑定虚拟手柄。设为 `0` 则完全按 Astris 的设置来，此时只有 Player 1 是手柄时鼠标才生效。 |
| `ASTRIS_MOUSE_DEBUG` | `0` | 记录 Astris 的每次输入调用，以及本工具发出的每个值。 |

`run.sh` 和 `build.sh` 的选项：

- `ASTRIS_APP=/path/to/Astris.app`：Astris 不在 `/Applications` 时指定路径。
- `ASTRIS_MOUSE_FOREGROUND=1`：让 Astris 留在终端前台运行，实时输出日志。

键位不在这里配置，而是直接读取 Astris 自己的输入设置。

## 常见问题

- **按 ⌥⌘M 没反应**：热键只在 Astris 是前台应用时生效，先点一下游戏窗口。`notifyutil -p dev.astrismouse.toggle` 不受焦点影响，随时可用。
- **怎么确认注入成功**：日志里应该能看到类似这几行：
  ```
  virtual gamepad "AstrisMouse" connected as controller 0 (startup)
  Application ConfigureInputs: Configured Gamepad 'AstrisMouse' for Player1   ← 游戏启动时
  panning ON (...) controller=0 virtual window="..."                         ← 按 ⌥⌘M 后
  ```
- **能开关平移但镜头不动**：Player 1 没有绑定到虚拟手柄。看日志里有没有 `Configured Keyboard for Player1` 或 `Gamepad ID '...' requested for Player1 but not found`。确认 `ASTRIS_MOUSE_TAKEOVER` 没有设成 `0`，并且 Astris 输入设置里的 Player 1 不是 *Invalid*。
- **上下视角反了**：设置 `ASTRIS_MOUSE_INVERT_Y=1`。
- **绑定的鼠标键没反应或按住会断**：先确认平移已开启（鼠标键绑定只在平移时生效），再看日志有没有 `ASTRIS_MOUSE_BUTTON_... 无法识别`。如果用了 Karabiner、BetterTouchTool 之类的改键工具，它们可能把长按右键改成了别的按键，Astris 就收不到原始的鼠标事件；给 Astris（Bundle ID `V380-Ori.Astris`）加一条例外规则即可。
- **改了 `config.env` 没反应**：本次启动的日志里应有 `config: live reload on, watching .../config.env`，每次保存后还会多一行 `[astris-launch] sent ...`。没有的话说明这个实例是用旧版本启动的，退出 Astris 重新 `./run.sh`。
- **编译时找不到 `libryujinx.dylib`**：用 `ASTRIS_APP` 指向你的 `Astris.app`。
- **其他问题**：用 `ASTRIS_MOUSE_DEBUG=1 ./run.sh` 启动并复现问题，然后把 `~/Library/Logs/AstrisMouse.log` 附在 issue 里。

## 卸载

- **回到原版 Astris**：退出 Astris，然后像平时一样从 Dock、Finder 或 Spotlight 打开即可。`Astris.app` 从未被修改，不需要任何还原操作。
- **删除编译产物和日志**：退出 Astris 后运行 `./uninstall.sh`。删掉整个目录即可彻底移除。

## 工作原理

1. `run.sh` 通过 `build/astris-launch` 启动 Astris，只在 Astris 进程里设置 `DYLD_INSERT_LIBRARIES`。Astris 的签名 entitlements（`com.apple.security.cs.allow-dyld-environment-variables` 和 `com.apple.security.cs.disable-library-validation`）允许这样做，无需重新签名。`astris-launch` 还会留下一个很小的监视进程，用 kqueue 盯着 `config.env`，文件一变就把内容通过管道送进 dylib（Astris 是沙盒进程，自己读不了这个文件）。Astris 退出时监视进程跟着退出。
2. `libAstrisMouse.dylib` 通过 dyld interpose 拦截 Astris 对 `libryujinx` 的调用：`update_options`、手柄连接与断开、摇杆、按键、键盘和 `stop_emulation`。
3. Astris 会把整份设置 JSON 交给 `ryujinx_update_options`。如果其中 Player 1 是 Keyboard，dylib 先把这一项改写成 `backend: Gamepad, controllerId: AstrisMouse` 再转交，然后调用 `ryujinx_connect_controller("AstrisMouse", ...)`，让 Player 1 绑定到虚拟手柄。如果 Player 1 本来就是手柄，配置原样转交，虚拟手柄改用该手柄的 ID 注册，在没有真实手柄时顶上。
4. Player 1 变成手柄后，`libryujinx` 不再把键盘映射给它，所以 dylib 从同一份配置里读取 Player 1 的键位，转发到虚拟手柄的摇杆和按键上。
5. 平移开启时，光标被隐藏并与鼠标解耦。每个鼠标事件都按事件时间戳换算成瞬时速度（最近几次位移 / 实际时间跨度），经过响应曲线、轻微低通和死区补偿后，立刻用 `ryujinx_set_controller_stick_axis` 写入右摇杆。另有一个精确定时器：下一次鼠标回报没按时到，就把摇杆归零，所以鼠标一停镜头大约一个回报周期内就停，不用等窗口排空。

## 开发

### 项目结构

| 路径 | 用途 |
|---|---|
| `Sources/AstrisMouse.swift` | 虚拟手柄生命周期、键盘转发、鼠标采样与滤波、热键、Darwin 通知 |
| `Sources/interpose.c` | libryujinx 调用的 dyld interpose 表 |
| `Sources/launcher.c` | `astris-launch`：在独立会话中启动 Astris，只向它注入 dylib，并监视 `config.env` 实现热更新 |
| `Sources/bridge.h`、`Sources/callbacks.h` | libryujinx C API 声明与 C 到 Swift 的回调 |
| `build.sh`、`run.sh`、`uninstall.sh` | 编译、启动、清理 |
| `config.env.example` | 配置模板 |

### libryujinx C API 备注

以下签名通过反汇编 Astris 1.0.32（arm64）得到，其他版本可能不同。

- `int32 ryujinx_connect_controller(const char *id, const char *name)`：返回槽位句柄；ID 已存在或没有输入管理器时返回 -1。
- `void ryujinx_disconnect_controller(const char *id)`
- `void ryujinx_set_controller_stick_axis(int32 controller, int32 stick, float x, float y)`：stick 0 为左摇杆、1 为右摇杆；y 向上为正；取值范围 -1 到 1。
- `void ryujinx_set_controller_button_pressed(int32 controller, int32 button, int32 pressed)`：button 0–16 依次为 A、B、X、Y、Minus、Home、Plus、LStick、RStick、L、R、DpadUp、DpadDown、DpadLeft、DpadRight、ZL、ZR。
- `void ryujinx_set_keyboard_key_pressed(int32 macKeyCode, int32 pressed)`
- `void ryujinx_update_options(const char *json)`：参数就是 Astris 存在 `RyujinxOptions` 偏好键下的那份 JSON；`playerInputConfig[].backend` 取值为 `Invalid`、`WindowKeyboard` 或 `Gamepad`。模拟运行中若输入部分有变化，`libryujinx` 会立即重新配置玩家。
- `ryujinx_start_emulation(const char *path)` / `ryujinx_stop_emulation(void)`

## 许可证

[MIT](LICENSE)
