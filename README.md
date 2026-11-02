# astris-mouse-panning

用鼠标驱动 [Astris](https://github.com/V380-Ori/Astris.Binaries)（macOS 上的 Switch 模拟器）里的**右摇杆模拟量**，替代 [MacRMB](https://github.com/ikoshura/MacRMB) 那种"按住 I/J/K/L 键"的数字输出，解决镜头一顿一顿的问题。

> Smooth mouse camera panning for the Astris emulator on macOS. A dylib injected into a single Astris launch registers a virtual Pro Controller and drives its right stick with filtered mouse velocity, instead of emulating digital I/J/K/L key presses. Astris.app itself is never modified.

非官方项目，与 Astris / V380-Ori 无关。本项目不包含、不分发、也不修改 Astris 的任何文件，使用风险自负。

## 它怎么做到的

- `run.sh` 用 `DYLD_INSERT_LIBRARIES` 把 `build/libAstrisMouse.dylib` 注入**本次启动**的 Astris 进程。Astris 自带的签名 entitlements 允许这样做，不需要改签名。
- dylib 在进程内通过 `ryujinx_connect_controller` 向 libryujinx 注册一个虚拟手柄，id 与 Astris「设置 → 输入」里 Player1 的 `controllerId` 相同（通常是 `Pro Controller`），于是 Player1 自动绑定到它。
- 开启平移后：隐藏并锁定光标，把鼠标位移换算成速度 → 曲线 → 低通滤波 → 抗死区，按显示刷新率写入虚拟手柄右摇杆（`ryujinx_set_controller_stick_axis`）。
- Player1 绑定到手柄后 Astris 不再把键盘映射给 Player1，所以 dylib 同时把 Astris 键位设置里的 WASD / IJKL / ZXCV / 方向键 / Q E U O / - = / F H 翻译成虚拟手柄的左摇杆、右摇杆与按键，键盘操作保持可用。键位在 Astris 里改了会自动跟随。
- 如果前端连上了真实手柄且 id 与配置相同，dylib 会让出虚拟手柄，鼠标改写到真实手柄的右摇杆；手柄断开后自动恢复虚拟手柄。

## 可回滚

- `/Applications/Astris.app` 内任何文件**从未被修改**。只有通过 `run.sh` 启动的那个进程才带注入。
- 想回到原生：⌘Q 退出，然后像平时一样从 Dock / Finder / Spotlight 打开 Astris 即可。
- 想清理：`./uninstall.sh`（删除编译产物与日志），或者直接删掉整个目录。

## 环境要求

- Apple Silicon Mac，macOS 15 及以上
- Xcode Command Line Tools（`xcode-select --install`），用于本地编译
- Astris，已在 1.0.32 上验证。默认路径是 `/Applications/Astris.app`，装在别处时用 `ASTRIS_APP=/path/to/Astris.app ./run.sh`

## 使用

```bash
git clone https://github.com/stevenup/astris-mouse-panning.git
cd astris-mouse-panning
./build.sh                     # 第一次需要（run.sh 也会自动编译）
./run.sh                       # 带注入启动 Astris（后台、脱离终端）
./run.sh "/path/to/game.xci"   # 启动后自动打开游戏
```

进游戏后：

| 操作 | 方式 |
|---|---|
| 开/关鼠标平移 | 在 Astris 里按 **⌥⌘M**，或终端 `notifyutil -p dev.astrismouse.toggle` |
| 强制关闭平移 | `notifyutil -p dev.astrismouse.stop`（切到别的 App、关游戏窗口、停止模拟也会自动关） |
| 看状态 | `notifyutil -p dev.astrismouse.probe` / `dev.astrismouse.diag`，然后看日志 |
| 日志 | `tail -f ~/Library/Logs/AstrisMouse.log` |

开启时有 "Tink" 提示音，关闭时 "Pop"。

正常日志应包含：

```
virtual gamepad "Pro Controller" connected as controller 0 (startup)
Application ConfigureInputs: Configured Gamepad 'AstrisMouse' for Player1   ← 游戏启动时
panning ON (hotkey) controller=0 virtual window="..."                     ← 按 ⌥⌘M 后
```

## 手感调参

复制 `config.env.example` 为 `config.env`，改完重新 `./run.sh`。常用项：

| 变量 | 默认 | 作用 |
|---|---|---|
| `ASTRIS_MOUSE_FULL_SPEED` | 400 | 鼠标多少 pt/s 时摇杆满偏。嫌慢就调小 |
| `ASTRIS_MOUSE_CURVE` | 1 | 响应曲线指数，1.5~2 低速更细腻 |
| `ASTRIS_MOUSE_SMOOTHING_MS` | 20 | 低通时间常数，越大越顺但越飘 |
| `ASTRIS_MOUSE_WINDOW_MS` | 24 | 速度估计窗口。125Hz 鼠标 24~32，1000Hz 可到 8~12 |
| `ASTRIS_MOUSE_ANTI_DEADZONE` | 0.10 | 与 Astris 的右摇杆死区一致 |
| `ASTRIS_MOUSE_INVERT_Y` | 0 | 反转 Y |
| `ASTRIS_MOUSE_TOGGLE` | cmd+alt+m | 热键 |
| `ASTRIS_MOUSE_DEBUG` | 0 | 记录每一次前端调用与本工具输出 |

## 与 MacRMB 的关系

两者可以同时装着，但不要同时开启两边的平移（MacRMB 是 ⌥⌘P，这里是 ⌥⌘M）。MacRMB 发出的 I/J/K/L 键在本工具下仍会被翻译成数字右摇杆，所以不开本工具的平移时 MacRMB 依然能用。

## 文件

- `Sources/interpose.c`：dyld interpose 表，拦截前端对 libryujinx 的 connect/disconnect/stick/button/keyboard/stop_emulation 调用。
- `Sources/AstrisMouse.swift`：虚拟手柄生命周期、键盘翻译、鼠标采样与滤波、热键与 Darwin 通知。
- `Sources/launcher.c`：`astris-launch`，在独立会话里 exec Astris，`DYLD_INSERT_LIBRARIES` 只进入 Astris 的环境（经过 tee/nohup 等系统二进制会失败）。
- `build.sh` / `run.sh` / `uninstall.sh` / `config.env.example`。

## 已确认的 libryujinx 接口（Astris 1.0.32，arm64）

- `int32 ryujinx_connect_controller(const char* id, const char* name)`：返回槽位句柄；id 已存在或无输入管理器时返回 -1。
- `void ryujinx_disconnect_controller(const char* id)`
- `void ryujinx_set_controller_stick_axis(int32 controller, int32 stick, float x, float y)`：stick 0 左 / 1 右，y 向上为正，范围 -1..1。
- `void ryujinx_set_controller_button_pressed(int32 controller, int32 button, int32 pressed)`：button 0..16 = A B X Y Minus Home Plus LStick RStick L R DpadUp DpadDown DpadLeft DpadRight ZL ZR。
- `void ryujinx_set_keyboard_key_pressed(int32 macKeyCode, int32 pressed)`
- `ryujinx_start_emulation(const char* path)` / `ryujinx_stop_emulation(void)`

## 许可证

[MIT](LICENSE)
