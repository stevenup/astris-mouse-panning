# astris-mouse-panning

[English](README.md) | 简体中文

为 [Astris](https://github.com/V380-Ori/Astris.Binaries)（macOS 上的 Nintendo Switch 模拟器）提供丝滑的模拟量鼠标镜头平移。

[MacRMB](https://github.com/ikoshura/MacRMB) 这类“鼠标转按键”的工具靠按住 I/J/K/L 来转动镜头，右摇杆只能收到 8 个方向上的满偏输入，所以镜头一顿一顿的。astris-mouse-panning 把鼠标速度换算成虚拟手柄右摇杆的模拟量，镜头转起来和用真手柄一样顺滑。

> [!NOTE]
> 本项目为非官方项目，与 Astris / V380-Ori 无关，不包含、不分发、也不修改 Astris 的任何文件。使用风险自负。

## 特性

- **模拟量右摇杆**：鼠标移动经过滤波后映射为连续的摇杆偏移，每个显示帧更新一次。
- **键盘照常可用**：自动读取 Astris 输入设置里 Player 1 的键位并转发给虚拟手柄，在 Astris 里改键位会立即生效。
- **真手柄优先**：Astris 连上 ID 与 Player 1 相同的真实手柄时，虚拟手柄自动让位，鼠标改为驱动真实手柄的右摇杆；真实手柄断开后，虚拟手柄自动恢复。
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

把 `config.env.example` 复制为 `config.env`，取消注释想修改的行，然后用 `./run.sh` 重新启动。只想临时试一个值时，可以写在命令前面，例如 `ASTRIS_MOUSE_FULL_SPEED=300 ./run.sh`。

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ASTRIS_MOUSE_FULL_SPEED` | `400` | 鼠标速度达到多少 pt/s 时摇杆满偏。越小越灵敏。 |
| `ASTRIS_MOUSE_CURVE` | `1` | 响应曲线指数。设为 1.5–2 时低速更细腻。 |
| `ASTRIS_MOUSE_SMOOTHING_MS` | `20` | 低通滤波时间常数。越大越顺滑，但也越“飘”。 |
| `ASTRIS_MOUSE_WINDOW_MS` | `24` | 速度估计窗口。125 Hz 鼠标建议 24–32，1000 Hz 鼠标可降到 8–12。 |
| `ASTRIS_MOUSE_ANTI_DEADZONE` | `0.10` | 非零输出的起始幅值。与 Astris 的右摇杆死区（默认 0.1）保持一致，微小移动才能被识别。 |
| `ASTRIS_MOUSE_OUTPUT_DEADZONE` | `0.02` | 幅值低于此值时输出 0，防止漂移。 |
| `ASTRIS_MOUSE_INVERT_Y` | `0` | 反转垂直方向。 |
| `ASTRIS_MOUSE_TOGGLE` | `cmd+alt+m` | 开关热键。修饰键：`cmd`、`alt`、`ctrl`、`shift`；按键：`a`–`z`、`0`–`9`、`f1`–`f15`、`space`、`tab`、`esc`、`return`，或直接写键码数字。 |
| `ASTRIS_MOUSE_SOUND` | `1` | 开关平移时播放提示音。 |
| `ASTRIS_MOUSE_CONTROLLER` | 自动 | 强制指定 libryujinx 的手柄句柄，一般不需要。 |
| `ASTRIS_MOUSE_DEBUG` | `0` | 记录 Astris 的每次输入调用，以及本工具发出的每个值。 |

`run.sh` 和 `build.sh` 的选项：

- `ASTRIS_APP=/path/to/Astris.app`：Astris 不在 `/Applications` 时指定路径。
- `ASTRIS_MOUSE_FOREGROUND=1`：让 Astris 留在终端前台运行，实时输出日志。

键位不在这里配置，而是直接读取 Astris 自己的输入设置。

## 常见问题

- **按 ⌥⌘M 没反应**：热键只在 Astris 是前台应用时生效，先点一下游戏窗口。`notifyutil -p dev.astrismouse.toggle` 不受焦点影响，随时可用。
- **怎么确认注入成功**：日志里应该能看到类似这几行：
  ```
  virtual gamepad "Pro Controller" connected as controller 0 (startup)
  Application ConfigureInputs: Configured Gamepad 'AstrisMouse' for Player1   ← 游戏启动时
  panning ON (...) controller=0 virtual window="..."                         ← 按 ⌥⌘M 后
  ```
- **上下视角反了**：设置 `ASTRIS_MOUSE_INVERT_Y=1`。
- **编译时找不到 `libryujinx.dylib`**：用 `ASTRIS_APP` 指向你的 `Astris.app`。
- **其他问题**：用 `ASTRIS_MOUSE_DEBUG=1 ./run.sh` 启动并复现问题，然后把 `~/Library/Logs/AstrisMouse.log` 附在 issue 里。

## 卸载

- **回到原版 Astris**：退出 Astris，然后像平时一样从 Dock、Finder 或 Spotlight 打开即可。`Astris.app` 从未被修改，不需要任何还原操作。
- **删除编译产物和日志**：退出 Astris 后运行 `./uninstall.sh`。删掉整个目录即可彻底移除。

## 工作原理

1. `run.sh` 通过 `build/astris-launch` 启动 Astris，只在 Astris 进程里设置 `DYLD_INSERT_LIBRARIES`。Astris 的签名 entitlements（`com.apple.security.cs.allow-dyld-environment-variables` 和 `com.apple.security.cs.disable-library-validation`）允许这样做，无需重新签名。
2. `libAstrisMouse.dylib` 通过 dyld interpose 拦截 Astris 对 `libryujinx` 的调用：手柄连接与断开、摇杆、按键、键盘和 `stop_emulation`。
3. 它用 Player 1 的 `controllerId`（通常是 `Pro Controller`）调用 `ryujinx_connect_controller`，让 Player 1 绑定到虚拟手柄。
4. Player 1 变成手柄后，Astris 不再把键盘映射给它，所以 dylib 从 Astris 的偏好设置里读取 Player 1 的键位，转发到虚拟手柄的摇杆和按键上。
5. 平移开启时，光标被隐藏并与鼠标解耦。每个显示帧都会把最近的鼠标位移换算成速度，经过响应曲线、低通滤波和死区补偿后，用 `ryujinx_set_controller_stick_axis` 写入右摇杆。

## 开发

### 项目结构

| 路径 | 用途 |
|---|---|
| `Sources/AstrisMouse.swift` | 虚拟手柄生命周期、键盘转发、鼠标采样与滤波、热键、Darwin 通知 |
| `Sources/interpose.c` | libryujinx 调用的 dyld interpose 表 |
| `Sources/launcher.c` | `astris-launch`：在独立会话中启动 Astris，并只向它注入 dylib |
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
- `ryujinx_start_emulation(const char *path)` / `ryujinx_stop_emulation(void)`

## 许可证

[MIT](LICENSE)
