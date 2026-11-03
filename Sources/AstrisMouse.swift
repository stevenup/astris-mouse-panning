import AppKit
import Foundation
import QuartzCore

// MARK: - 日志

private let amTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func amLog(_ message: @autoclosure () -> String) {
    let line = "[AstrisMouse \(amTimeFormatter.string(from: Date()))] \(message())\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - 配置（全部来自环境变量，见 config.env.example）

struct AMConfig {
    var fullSpeed = 400.0          // 鼠标速度（pt/s）达到该值时摇杆满偏
    var curve = 1.0                // 响应曲线指数，>1 低速更细腻
    var smoothingTau = 0.020       // 一阶低通时间常数（秒）
    var window = 0.024             // 速度估计窗口（秒）
    var antiDeadzone = 0.10        // 补偿 Astris 侧 deadzoneRight
    var outputDeadzone = 0.02      // 低于此幅值输出 0
    var invertY = false
    var toggleKeyCode: UInt16 = 46 // M
    var toggleModifiers: NSEvent.ModifierFlags = [.command, .option]
    var toggleDescription = "cmd+alt+m"
    var controllerOverride: Int32?
    var takeover = true            // Player1 不是手柄后端时，改写传给 libryujinx 的配置让它绑定虚拟手柄
    var debug = false
    var sound = true

    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
        "`": 50, "delete": 51, "esc": 53, "escape": 53, "f5": 96, "f6": 97, "f7": 98, "f3": 99,
        "f8": 100, "f9": 101, "f11": 103, "f13": 105, "f14": 107, "f10": 109, "f12": 111,
        "f15": 113, "f4": 118, "f2": 120, "f1": 122,
    ]

    static func load() -> AMConfig {
        var c = AMConfig()
        let env = ProcessInfo.processInfo.environment
        func num(_ key: String) -> Double? {
            env[key].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        func flag(_ key: String) -> Bool? {
            env[key].map { ["1", "true", "yes", "on"].contains($0.lowercased()) }
        }
        if let v = num("ASTRIS_MOUSE_FULL_SPEED"), v > 0 { c.fullSpeed = v }
        if let v = num("ASTRIS_MOUSE_CURVE"), v > 0 { c.curve = v }
        if let v = num("ASTRIS_MOUSE_SMOOTHING_MS"), v >= 0 { c.smoothingTau = v / 1000 }
        if let v = num("ASTRIS_MOUSE_WINDOW_MS"), v > 0 { c.window = v / 1000 }
        if let v = num("ASTRIS_MOUSE_ANTI_DEADZONE"), v >= 0, v < 1 { c.antiDeadzone = v }
        if let v = num("ASTRIS_MOUSE_OUTPUT_DEADZONE"), v >= 0, v < 1 { c.outputDeadzone = v }
        if let v = flag("ASTRIS_MOUSE_INVERT_Y") { c.invertY = v }
        if let v = flag("ASTRIS_MOUSE_DEBUG") { c.debug = v }
        if let v = flag("ASTRIS_MOUSE_SOUND") { c.sound = v }
        if let v = flag("ASTRIS_MOUSE_TAKEOVER") { c.takeover = v }
        if let v = num("ASTRIS_MOUSE_CONTROLLER") { c.controllerOverride = Int32(v) }
        if let spec = env["ASTRIS_MOUSE_TOGGLE"]?.lowercased(), !spec.isEmpty {
            var mods: NSEvent.ModifierFlags = []
            var key: UInt16?
            for token in spec.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                switch token {
                case "cmd", "command", "⌘": mods.insert(.command)
                case "alt", "opt", "option", "⌥": mods.insert(.option)
                case "ctrl", "control", "⌃": mods.insert(.control)
                case "shift", "⇧": mods.insert(.shift)
                default:
                    if let k = keyCodes[token] { key = k } else if let n = UInt16(token) { key = n }
                }
            }
            if let key {
                c.toggleKeyCode = key
                c.toggleModifiers = mods
                c.toggleDescription = spec
            } else {
                amLog("ASTRIS_MOUSE_TOGGLE=\(spec) 无法解析，沿用默认 cmd+alt+m")
            }
        }
        return c
    }
}

// MARK: - Astris 键位配置 → 虚拟手柄映射

// libryujinx C API 的按钮编号（内部再查表转成 GamepadButtonInputId）
enum AMButton: Int32 {
    case a = 0, b = 1, x = 2, y = 3, minus = 4, home = 5, plus = 6
    case leftStick = 7, rightStick = 8, l = 9, r = 10
    case dpadUp = 11, dpadDown = 12, dpadLeft = 13, dpadRight = 14, zl = 15, zr = 16
}

struct AMStickKeys {
    var up: Int32?
    var down: Int32?
    var left: Int32?
    var right: Int32?

    func contains(_ key: Int32) -> Bool { key == up || key == down || key == left || key == right }

    func value(_ keysDown: Set<Int32>) -> (x: Float, y: Float) {
        func on(_ k: Int32?) -> Float { k.map { keysDown.contains($0) ? 1 : 0 } ?? 0 }
        return (on(right) - on(left), on(up) - on(down))
    }
}

struct AMBindings {
    // Player1 不是手柄后端时，虚拟手柄用这个独立 id 注册，避免和物理手柄撞名
    static let takeoverId = "AstrisMouse"

    var controllerId = "Pro Controller"
    var backend = "unknown"          // Astris 的 Player1 backend：Invalid / WindowKeyboard / Gamepad
    var takeover = false             // 是否需要把 Player1 改写成绑定虚拟手柄
    var useNintendoLayout = false
    var buttons: [Int32: AMButton] = [:]
    var leftStick = AMStickKeys()
    var rightStick = AMStickKeys()
    var source = "default"

    // Ryujinx Key 枚举名 → macOS 键码
    static let keyCodes: [String: Int32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11,
        "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35,
        "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
        "Number1": 18, "Number2": 19, "Number3": 20, "Number4": 21, "Number6": 22, "Number5": 23,
        "Number9": 25, "Number7": 26, "Number8": 28, "Number0": 29,
        "Plus": 24, "Minus": 27, "BracketRight": 30, "BracketLeft": 33, "Quote": 39, "Semicolon": 41,
        "BackSlash": 42, "Comma": 43, "Slash": 44, "Period": 47, "Grave": 50, "Tilde": 50,
        "Enter": 36, "Tab": 48, "Space": 49, "BackSpace": 51, "Escape": 53, "CapsLock": 57,
        "Insert": 114, "Home": 115, "PageUp": 116, "Delete": 117, "End": 119, "PageDown": 121,
        "Left": 123, "Right": 124, "Down": 125, "Up": 126,
        "ShiftLeft": 56, "ShiftRight": 60, "ControlLeft": 59, "ControlRight": 62,
        "AltLeft": 58, "AltRight": 61, "WinLeft": 55, "WinRight": 54,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100,
        "F9": 101, "F10": 109, "F11": 103, "F12": 111, "F13": 105, "F14": 107, "F15": 113,
        "Keypad0": 82, "Keypad1": 83, "Keypad2": 84, "Keypad3": 85, "Keypad4": 86, "Keypad5": 87,
        "Keypad6": 88, "Keypad7": 89, "Keypad8": 90, "Keypad9": 92, "KeypadDivide": 75,
        "KeypadMultiply": 67, "KeypadSubtract": 78, "KeypadAdd": 69, "KeypadDecimal": 65, "KeypadEnter": 76,
    ]

    static func player1(in root: [String: Any]) -> [String: Any]? {
        guard let players = root["playerInputConfig"] as? [[String: Any]] else { return nil }
        return players.first(where: { ($0["playerIndex"] as? String) == "Player1" }) ?? players.first
    }

    static func load(takeoverEnabled: Bool) -> AMBindings {
        guard let data = UserDefaults.standard.data(forKey: "RyujinxOptions"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let b = AMBindings()
            amLog("bindings: RyujinxOptions 不可读，使用默认 controllerId=\"\(b.controllerId)\"，键盘映射为空")
            return b
        }
        return parse(root, source: "prefs", takeoverEnabled: takeoverEnabled)
    }

    static func parse(_ root: [String: Any], source: String, takeoverEnabled: Bool) -> AMBindings {
        var b = AMBindings()
        guard let p1 = player1(in: root) else {
            amLog("bindings(\(source)): 找不到 playerInputConfig，使用默认 controllerId=\"\(b.controllerId)\"")
            return b
        }
        b.source = source
        b.backend = (p1["backend"] as? String) ?? "missing"
        let configuredId = (p1["controllerId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch b.backend {
        case "Gamepad" where configuredId != nil:
            b.controllerId = configuredId!
        case "Invalid":
            b.controllerId = configuredId ?? AMBindings.takeoverId
        default:
            // WindowKeyboard，或 Gamepad 但没选手柄：libryujinx 只会给 Player1 配键盘，
            // 需要我们把它改写成绑定虚拟手柄，键盘再由我们转成手柄按键
            b.takeover = takeoverEnabled
            b.controllerId = takeoverEnabled ? AMBindings.takeoverId : (configuredId ?? "Pro Controller")
        }
        b.useNintendoLayout = (p1["useNintendoLayout"] as? Bool) ?? false

        func key(_ section: String, _ field: String) -> Int32? {
            guard let sec = p1[section] as? [String: Any], let name = sec[field] as? String else { return nil }
            return keyCodes[name]
        }
        func bind(_ section: String, _ field: String, _ button: AMButton) {
            if let k = key(section, field) { b.buttons[k] = button }
        }
        let nintendo = b.useNintendoLayout
        bind("rightJoycon", "buttonA", nintendo ? .b : .a)
        bind("rightJoycon", "buttonB", nintendo ? .a : .b)
        bind("rightJoycon", "buttonX", nintendo ? .y : .x)
        bind("rightJoycon", "buttonY", nintendo ? .x : .y)
        bind("rightJoycon", "buttonPlus", .plus)
        bind("rightJoycon", "buttonR", .r)
        bind("rightJoycon", "buttonZr", .zr)
        bind("leftJoycon", "buttonMinus", .minus)
        bind("leftJoycon", "buttonL", .l)
        bind("leftJoycon", "buttonZl", .zl)
        bind("leftJoycon", "dpadUp", .dpadUp)
        bind("leftJoycon", "dpadDown", .dpadDown)
        bind("leftJoycon", "dpadLeft", .dpadLeft)
        bind("leftJoycon", "dpadRight", .dpadRight)
        bind("leftJoyconStick", "stickButton", .leftStick)
        bind("rightJoyconStick", "stickButton", .rightStick)
        b.leftStick = AMStickKeys(
            up: key("leftJoyconStick", "stickUp"), down: key("leftJoyconStick", "stickDown"),
            left: key("leftJoyconStick", "stickLeft"), right: key("leftJoyconStick", "stickRight"))
        b.rightStick = AMStickKeys(
            up: key("rightJoyconStick", "stickUp"), down: key("rightJoyconStick", "stickDown"),
            left: key("rightJoyconStick", "stickLeft"), right: key("rightJoyconStick", "stickRight"))
        return b
    }

    // 需要接管时返回改写后的整份配置：Player1 → Gamepad + 虚拟手柄 id，其余字段原样保留
    func rewrittenOptions(_ root: [String: Any]) -> [String: Any]? {
        guard takeover, var players = root["playerInputConfig"] as? [[String: Any]],
              let idx = players.firstIndex(where: { ($0["playerIndex"] as? String) == "Player1" })
        else { return nil }
        players[idx]["backend"] = "Gamepad"
        players[idx]["controllerId"] = AMBindings.takeoverId
        var out = root
        out["playerInputConfig"] = players
        return out
    }

    var player1Status: String {
        switch (backend, takeover) {
        case ("Invalid", _):
            return "warning: Astris 里 Player1 的输入是 Invalid（未启用），鼠标和键盘都进不了游戏；请在 Astris 设置里把 Player1 设为 Keyboard 或 Gamepad"
        case (_, true):
            return "Player1 在 Astris 里是 \(backend)，注入后改写为 Gamepad/\"\(AMBindings.takeoverId)\"（只改本进程交给 libryujinx 的配置，Astris 设置文件不变）"
        case ("Gamepad", false):
            return "Player1 在 Astris 里是 Gamepad controllerId=\"\(controllerId)\"，沿用；没有同名物理手柄时由虚拟手柄顶替"
        default:
            return "Player1 在 Astris 里是 \(backend)，未接管（ASTRIS_MOUSE_TAKEOVER=0），鼠标不会生效"
        }
    }

    var summary: String {
        "controllerId=\"\(controllerId)\" backend=\(backend) takeover=\(takeover) nintendoLayout=\(useNintendoLayout) buttons=\(buttons.count) leftStickKeys=\(leftStick.up != nil) rightStickKeys=\(rightStick.up != nil) source=\(source)"
    }

    // 不含 source：同一份配置不管来自偏好还是 update_options 都算相同
    var signature: String {
        let keys = buttons.map { "\($0.key)->\($0.value)" }.sorted().joined(separator: " ")
        let sticks = "\(leftStick.up ?? -1),\(leftStick.down ?? -1),\(leftStick.left ?? -1),\(leftStick.right ?? -1)|\(rightStick.up ?? -1),\(rightStick.down ?? -1),\(rightStick.left ?? -1),\(rightStick.right ?? -1)"
        return "\(controllerId)|\(backend)|\(takeover)|\(useNintendoLayout) \(keys) \(sticks)"
    }
}

// MARK: - 共享状态

final class AMState {
    static let shared = AMState()

    let lock = NSLock()
    let cfg: AMConfig
    var bindings: AMBindings

    private init() {
        cfg = AMConfig.load()
        bindings = AMBindings.load(takeoverEnabled: cfg.takeover)
    }

    var installed = false
    var active = false
    var virtualHandle: Int32 = -1
    var physical: [String: Int32] = [:]
    var keysDown = Set<Int32>()
    var toggleKeyDown = false
    var connectFailureLogged = false

    var frontendRight: (x: Float, y: Float) = (0, 0)
    var samples: [(t: Double, dx: Double, dy: Double)] = []
    var filtered: (x: Double, y: Double) = (0, 0)
    var lastSent: (x: Float, y: Float) = (0, 0)
    var startTime: Double = 0
    var moves = 0
    var sends = 0
    var swallowed = 0
    var frontendStickCalls = 0
    var frontendButtonCalls = 0
    var frontendKeyboardCalls = 0

    var displayLink: CADisplayLink?
    var ensureTimer: Timer?
    var monitors: [Any] = []
    var pinnedWindow: NSWindow?
    var pinnedWindowAcceptedMouseMoved = false
    var hideCount = 0
    var lastCursorCheck: Double = 0
    var notifyTokens: [Int32] = []

    // 鼠标输出的目标：显式指定 > 前端连上的同名物理手柄 > 我们的虚拟手柄
    var handle: Int32? {
        if let o = cfg.controllerOverride { return o }
        if let p = physical[bindings.controllerId] { return p }
        return virtualHandle >= 0 ? virtualHandle : nil
    }

    var usingPhysical: Bool { physical[bindings.controllerId] != nil }
}

// MARK: - 虚拟手柄生命周期

func amEnsureVirtualGamepad(reason: String) {
    let s = AMState.shared
    s.lock.lock()
    let id = s.bindings.controllerId
    let need = s.virtualHandle < 0 && s.physical[id] == nil
    s.lock.unlock()
    guard need else { return }

    let h = ryujinx_connect_controller(id, "AstrisMouse")
    if h >= 0 {
        s.lock.lock()
        s.virtualHandle = h
        s.connectFailureLogged = false
        s.lock.unlock()
        amLog("virtual gamepad \"\(id)\" connected as controller \(h) (\(reason))")
        amPushKeyboardState()
    } else if !s.connectFailureLogged {
        s.connectFailureLogged = true
        amLog("virtual gamepad \"\(id)\" connect failed (\(reason)); will keep retrying every 2s")
    }
}

func amReleaseVirtualGamepad(reason: String) {
    let s = AMState.shared
    s.lock.lock()
    let h = s.virtualHandle
    let id = s.bindings.controllerId
    s.virtualHandle = -1
    s.lock.unlock()
    guard h >= 0 else { return }
    ryujinx_disconnect_controller(id)
    amLog("virtual gamepad \"\(id)\" (controller \(h)) disconnected (\(reason))")
}

private func amReloadBindings() {
    let s = AMState.shared
    amApplyBindings(AMBindings.load(takeoverEnabled: s.cfg.takeover))
}

private func amApplyBindings(_ fresh: AMBindings) {
    let s = AMState.shared
    s.lock.lock()
    let old = s.bindings
    let changed = fresh.signature != old.signature
    s.bindings = fresh
    s.lock.unlock()
    guard changed else { return }
    amLog("bindings reloaded: \(fresh.summary)")
    if fresh.backend != old.backend || fresh.takeover != old.takeover || fresh.controllerId != old.controllerId {
        amLog(fresh.player1Status)
    }
    amPushKeyboardState()
    if fresh.controllerId != old.controllerId {
        // 旧 id 的虚拟手柄要先摘掉，否则 libryujinx 里会留下一个没人用的手柄
        s.lock.lock()
        let h = s.virtualHandle
        s.virtualHandle = -1
        s.lock.unlock()
        if h >= 0 {
            ryujinx_disconnect_controller(old.controllerId)
            amLog("virtual gamepad \"\(old.controllerId)\" (controller \(h)) disconnected (controllerId changed -> \"\(fresh.controllerId)\")")
        }
        amEnsureVirtualGamepad(reason: "controllerId changed")
    }
}

// 前端每次把 RyujinxOptions 交给 libryujinx 都会经过这里（启动、改设置）
@_cdecl("am_rewrite_options")
public func amRewriteOptions(_ json: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let json else { return nil }
    let s = AMState.shared
    let data = Data(bytes: json, count: strlen(json))
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        amLog("options: 前端传给 libryujinx 的 JSON 无法解析，原样放行")
        return nil
    }
    let fresh = AMBindings.parse(root, source: "update_options", takeoverEnabled: s.cfg.takeover)
    amApplyBindings(fresh)
    guard let patched = fresh.rewrittenOptions(root),
          let out = try? JSONSerialization.data(withJSONObject: patched),
          let text = String(data: out, encoding: .utf8)
    else { return nil }
    if s.cfg.debug { amLog("options: Player1 rewritten (\(data.count) -> \(out.count) bytes)") }
    return strdup(text)
}

// MARK: - 键盘 → 虚拟手柄

private func amPushKeyboardState() {
    let s = AMState.shared
    s.lock.lock()
    let h = s.virtualHandle
    let b = s.bindings
    let keys = s.keysDown
    let active = s.active
    s.lock.unlock()
    guard h >= 0 else { return }
    for (key, button) in b.buttons {
        ryujinx_set_controller_button_pressed(h, button.rawValue, keys.contains(key) ? 1 : 0)
    }
    let left = b.leftStick.value(keys)
    ryujinx_set_controller_stick_axis(h, 0, left.x, left.y)
    if !active {
        let right = b.rightStick.value(keys)
        ryujinx_set_controller_stick_axis(h, 1, right.x, right.y)
    }
}

// MARK: - 来自 interpose.c 的回调（任意线程）

@_cdecl("am_on_stick_axis")
public func amOnStickAxis(_ controller: Int32, _ stick: Int32, _ x: Float, _ y: Float) -> Bool {
    let s = AMState.shared
    s.lock.lock()
    s.frontendStickCalls += 1
    let debug = s.cfg.debug
    var swallow = false
    if stick == 1 && s.active && controller == s.handle {
        s.frontendRight = (x, y)
        s.swallowed += 1
        swallow = true
    }
    s.lock.unlock()
    if debug {
        amLog("frontend stick_axis(controller=\(controller), stick=\(stick), x=\(x), y=\(y))\(swallow ? " [swallowed]" : "")")
    }
    return swallow
}

@_cdecl("am_on_button_pressed")
public func amOnButtonPressed(_ controller: Int32, _ button: Int32, _ pressed: Int32) {
    let s = AMState.shared
    s.lock.lock()
    s.frontendButtonCalls += 1
    let debug = s.cfg.debug
    s.lock.unlock()
    if debug {
        amLog("frontend button_pressed(controller=\(controller), button=\(button), pressed=\(pressed))")
    }
}

@_cdecl("am_before_connect_controller")
public func amBeforeConnectController(_ id: UnsafePointer<CChar>?) {
    guard let id else { return }
    let idText = String(cString: id)
    let s = AMState.shared
    s.lock.lock()
    let clash = idText == s.bindings.controllerId && s.virtualHandle >= 0
    s.lock.unlock()
    if clash {
        amReleaseVirtualGamepad(reason: "physical controller \"\(idText)\" connecting")
    }
}

@_cdecl("am_on_connect_controller")
public func amOnConnectController(_ id: UnsafePointer<CChar>?, _ name: UnsafePointer<CChar>?, _ handle: Int32) {
    let s = AMState.shared
    let idText = id.map { String(cString: $0) } ?? "nil"
    let nameText = name.map { String(cString: $0) } ?? "nil"
    s.lock.lock()
    if handle >= 0 { s.physical[idText] = handle }
    s.lock.unlock()
    amLog("frontend connect_controller(id=\"\(idText)\", name=\"\(nameText)\") -> handle \(handle)")
}

@_cdecl("am_on_disconnect_controller")
public func amOnDisconnectController(_ id: UnsafePointer<CChar>?) {
    let idText = id.map { String(cString: $0) } ?? "nil"
    let s = AMState.shared
    s.lock.lock()
    s.physical.removeValue(forKey: idText)
    s.lock.unlock()
    amLog("frontend disconnect_controller(id=\"\(idText)\")")
    DispatchQueue.main.async { amEnsureVirtualGamepad(reason: "physical controller disconnected") }
}

@_cdecl("am_before_stop_emulation")
public func amBeforeStopEmulation() {
    DispatchQueue.main.async {
        if AMState.shared.active { amStop(reason: "emulation stopping") }
    }
    amReleaseVirtualGamepad(reason: "emulation stopping")
}

// Astris 自己的 NSEvent 本地监视器会吞掉游戏中的按键，我们的监视器未必能看到热键；
// 这里在前端转发键盘事件的必经之路上再识别一次。
private func amCurrentModifiers(forKey key: Int32) -> NSEvent.ModifierFlags {
    let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    if Thread.isMainThread, let e = NSApp.currentEvent,
       e.type == .keyDown || e.type == .keyUp, e.keyCode == UInt16(truncatingIfNeeded: key) {
        return e.modifierFlags.intersection(mask)
    }
    return NSEvent.modifierFlags.intersection(mask)
}

@_cdecl("am_on_keyboard_key_pressed")
public func amOnKeyboardKeyPressed(_ key: Int32, _ pressed: Int32) -> Bool {
    let s = AMState.shared
    if key == Int32(s.cfg.toggleKeyCode) {
        if pressed != 0 {
            if amCurrentModifiers(forKey: key) == s.cfg.toggleModifiers {
                s.lock.lock()
                let wasDown = s.toggleKeyDown
                s.toggleKeyDown = true
                s.lock.unlock()
                if !wasDown { DispatchQueue.main.async { amToggle(reason: "hotkey via keyboard hook") } }
                return true
            }
        } else {
            s.lock.lock()
            let swallow = s.toggleKeyDown
            s.toggleKeyDown = false
            s.lock.unlock()
            if swallow { return true }
        }
    }
    s.lock.lock()
    s.frontendKeyboardCalls += 1
    if pressed != 0 { s.keysDown.insert(key) } else { s.keysDown.remove(key) }
    let h = s.virtualHandle
    let b = s.bindings
    let keys = s.keysDown
    let active = s.active
    let debug = s.cfg.debug
    s.lock.unlock()
    if debug {
        amLog("frontend keyboard_key_pressed(key=\(key), pressed=\(pressed))")
    }
    guard h >= 0 else { return false }
    if let button = b.buttons[key] {
        ryujinx_set_controller_button_pressed(h, button.rawValue, pressed != 0 ? 1 : 0)
        if debug { amLog("emu button \(button) pressed=\(pressed) -> controller \(h)") }
    }
    if b.leftStick.contains(key) {
        let v = b.leftStick.value(keys)
        ryujinx_set_controller_stick_axis(h, 0, v.x, v.y)
        if debug { amLog("emu left stick (\(v.x), \(v.y)) -> controller \(h)") }
    }
    if b.rightStick.contains(key) && !active {
        let v = b.rightStick.value(keys)
        ryujinx_set_controller_stick_axis(h, 1, v.x, v.y)
        if debug { amLog("emu right stick (\(v.x), \(v.y)) -> controller \(h)") }
    }
    return false
}

// MARK: - 安装（主线程）

@objc final class AMTicker: NSObject {
    static let shared = AMTicker()

    @objc func tick(_ link: CADisplayLink) {
        amTick(dt: max(link.duration, 1.0 / 240.0))
    }
}

func amInstall() {
    let s = AMState.shared
    guard !s.installed else { return }
    s.installed = true
    let cfg = s.cfg

    if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: { event in
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.keyCode == cfg.toggleKeyCode && mods == cfg.toggleModifiers else { return event }
        if event.type == .keyDown && !event.isARepeat {
            amToggle(reason: "hotkey via event monitor")
        }
        return nil
    }) {
        s.monitors.append(m)
    }

    if let m = NSEvent.addLocalMonitorForEvents(
        matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged],
        handler: { event in
            guard AMState.shared.active else { return event }
            amAccumulate(dx: event.deltaX, dy: event.deltaY)
            return nil
        }
    ) {
        s.monitors.append(m)
    }

    let nc = NotificationCenter.default
    nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
        if AMState.shared.active { amStop(reason: "app resigned active") }
    }
    nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
        let s = AMState.shared
        if s.active, let w = note.object as? NSWindow, w === s.pinnedWindow {
            amStop(reason: "pinned window closed")
        }
    }
    nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
        amReloadBindings()
    }

    amRegisterNotification("dev.astrismouse.toggle") { amToggle(reason: "notify") }
    amRegisterNotification("dev.astrismouse.stop") { if AMState.shared.active { amStop(reason: "notify") } }
    amRegisterNotification("dev.astrismouse.probe") { amProbe() }
    amRegisterNotification("dev.astrismouse.diag") { amDiag() }

    let timer = Timer(timeInterval: 2.0, repeats: true) { _ in amEnsureVirtualGamepad(reason: "timer") }
    RunLoop.main.add(timer, forMode: .common)
    s.ensureTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { amEnsureVirtualGamepad(reason: "startup") }

    amLog("installed: toggle=\(cfg.toggleDescription) fullSpeed=\(cfg.fullSpeed)pt/s curve=\(cfg.curve) smoothing=\(Int(cfg.smoothingTau * 1000))ms window=\(Int(cfg.window * 1000))ms antiDeadzone=\(cfg.antiDeadzone) invertY=\(cfg.invertY) controller=\(cfg.controllerOverride.map(String.init) ?? "auto") debug=\(cfg.debug)")
    amLog("bindings: \(s.bindings.summary)")
    amLog(s.bindings.player1Status)
}

private func amRegisterNotification(_ name: String, _ handler: @escaping () -> Void) {
    var token: Int32 = 0
    let status = notify_register_dispatch(name, &token, DispatchQueue.main) { _ in handler() }
    if status == NOTIFY_STATUS_OK {
        AMState.shared.notifyTokens.append(token)
    } else {
        amLog("notify_register_dispatch(\(name)) failed: \(status)")
    }
}

// MARK: - 开关

func amToggle(reason: String) {
    if AMState.shared.active {
        amStop(reason: reason)
    } else {
        amStart(reason: reason)
    }
}

private func amCocoaToCG(_ p: NSPoint) -> CGPoint {
    let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
    return CGPoint(x: p.x, y: primaryMaxY - p.y)
}

func amStart(reason: String) {
    let s = AMState.shared
    guard !s.active else { return }
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
        amLog("start refused (\(reason)): no window")
        return
    }
    amEnsureVirtualGamepad(reason: "panning ON")
    if s.handle == nil {
        amLog("warning: no controller handle yet; mouse input will be ignored until one appears")
    }
    if s.bindings.backend != "Gamepad" && !s.bindings.takeover {
        amLog(s.bindings.player1Status)
    }

    s.pinnedWindow = window
    s.pinnedWindowAcceptedMouseMoved = window.acceptsMouseMovedEvents
    window.acceptsMouseMovedEvents = true

    let center = amCocoaToCG(NSPoint(x: window.frame.midX, y: window.frame.midY))
    CGWarpMouseCursorPosition(center)
    CGAssociateMouseAndMouseCursorPosition(0)
    NSCursor.hide()
    s.hideCount = 1

    s.lock.lock()
    s.samples.removeAll()
    s.filtered = (0, 0)
    s.lastSent = (0, 0)
    s.frontendRight = (0, 0)
    s.moves = 0
    s.sends = 0
    s.swallowed = 0
    s.startTime = CACurrentMediaTime()
    s.active = true
    s.lock.unlock()

    let link = window.displayLink(target: AMTicker.shared, selector: #selector(AMTicker.tick(_:)))
    link.add(to: .main, forMode: .common)
    s.displayLink = link

    if s.cfg.sound { NSSound(named: "Tink")?.play() }
    amLog("panning ON (\(reason)) controller=\(s.handle.map(String.init) ?? "none") \(s.usingPhysical ? "physical" : "virtual") window=\"\(window.title)\" pinned at \(center)")
}

func amStop(reason: String) {
    let s = AMState.shared
    guard s.active else { return }

    s.lock.lock()
    s.active = false
    let restore: (x: Float, y: Float) = s.usingPhysical ? s.frontendRight : s.bindings.rightStick.value(s.keysDown)
    let handle = s.handle
    let stats = (s.moves, s.sends, s.swallowed)
    s.lock.unlock()

    s.displayLink?.invalidate()
    s.displayLink = nil

    CGAssociateMouseAndMouseCursorPosition(1)
    while s.hideCount > 0 {
        NSCursor.unhide()
        s.hideCount -= 1
    }
    if let w = s.pinnedWindow {
        w.acceptsMouseMovedEvents = s.pinnedWindowAcceptedMouseMoved
    }
    s.pinnedWindow = nil

    if let handle {
        ryujinx_set_controller_stick_axis(handle, 1, restore.x, restore.y)
    }
    s.lastSent = restore

    if s.cfg.sound { NSSound(named: "Pop")?.play() }
    amLog("panning OFF (\(reason)) moves=\(stats.0) sends=\(stats.1) swallowedFrontend=\(stats.2)")
}

// MARK: - 采样与输出

private func amAccumulate(dx: CGFloat, dy: CGFloat) {
    let s = AMState.shared
    let now = CACurrentMediaTime()
    s.lock.lock()
    // 刚 warp 过的前 60ms 内 delta 不可信，丢弃
    if now - s.startTime > 0.06 {
        s.samples.append((now, Double(dx), Double(dy)))
        s.moves += 1
    }
    s.lock.unlock()
}

private func amTick(dt: Double) {
    let s = AMState.shared
    let cfg = s.cfg
    let now = CACurrentMediaTime()

    s.lock.lock()
    guard s.active else { s.lock.unlock(); return }
    let cutoff = now - cfg.window
    s.samples.removeAll { $0.t < cutoff }
    var sumX = 0.0, sumY = 0.0
    for sample in s.samples {
        sumX += sample.dx
        sumY += sample.dy
    }
    let frontend = s.frontendRight
    s.lock.unlock()

    // 窗口平均速度 → 目标摇杆向量（y 轴向上为正；Cocoa deltaY 向下为正）
    var targetX = (sumX / cfg.window) / cfg.fullSpeed
    var targetY = -(sumY / cfg.window) / cfg.fullSpeed
    if cfg.invertY { targetY = -targetY }
    let targetMag = (targetX * targetX + targetY * targetY).squareRoot()
    if targetMag > 0 {
        let shaped = pow(min(targetMag, 1.0), cfg.curve)
        targetX *= shaped / targetMag
        targetY *= shaped / targetMag
    }

    let alpha = cfg.smoothingTau > 0 ? 1 - exp(-dt / cfg.smoothingTau) : 1
    s.filtered.x += (targetX - s.filtered.x) * alpha
    s.filtered.y += (targetY - s.filtered.y) * alpha

    var outX = s.filtered.x
    var outY = s.filtered.y
    let outMag = (outX * outX + outY * outY).squareRoot()
    if outMag < cfg.outputDeadzone {
        outX = 0
        outY = 0
    } else if cfg.antiDeadzone > 0 {
        let scaled = cfg.antiDeadzone + (1 - cfg.antiDeadzone) * min(outMag, 1.0)
        outX *= scaled / outMag
        outY *= scaled / outMag
    }

    var out: (x: Float, y: Float) = (Float(outX), Float(outY))
    if (frontend.x * frontend.x + frontend.y * frontend.y).squareRoot() > 0.05 {
        out = frontend
    }
    amSend(out)

    // Astris 自己的 hide/unhide 可能把光标放出来；周期性补一次 hide，计数在 stop 时成对归还
    if now - s.lastCursorCheck > 2.0 {
        s.lastCursorCheck = now
        if NSApp.isActive && s.hideCount < 3 {
            NSCursor.hide()
            s.hideCount += 1
        }
    }
}

private func amSend(_ v: (x: Float, y: Float)) {
    let s = AMState.shared
    if v.x == 0 && v.y == 0 && s.lastSent.x == 0 && s.lastSent.y == 0 { return }
    guard let handle = s.handle else { return }
    ryujinx_set_controller_stick_axis(handle, 1, v.x, v.y)
    s.lastSent = v
    s.sends += 1
    if s.cfg.debug && s.sends % 30 == 0 {
        amLog("send stick_axis(controller=\(handle), stick=1, x=\(v.x), y=\(v.y)) samples=\(s.samples.count)")
    }
}

// MARK: - 诊断（notifyutil -p dev.astrismouse.probe / .diag）

private func amProbe() {
    let s = AMState.shared
    s.lock.lock()
    let summary = "probe: active=\(s.active) controller=\(s.handle.map(String.init) ?? "none") virtual=\(s.virtualHandle) physical=\(s.physical) keysDown=\(s.keysDown.sorted()) frontendRight=\(s.frontendRight) frontendCalls(stick=\(s.frontendStickCalls) button=\(s.frontendButtonCalls) keyboard=\(s.frontendKeyboardCalls)) moves=\(s.moves) sends=\(s.sends) swallowed=\(s.swallowed)"
    s.lock.unlock()
    amLog(summary)
    amLog("probe: isActive=\(NSApp.isActive) keyWindow=\"\(NSApp.keyWindow?.title ?? "nil")\" firstResponder=\(NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") windows=\(NSApp.windows.filter { $0.isVisible }.map { $0.title })")

    let env = ProcessInfo.processInfo.environment
    guard let codeText = env["ASTRIS_MOUSE_PROBE_KEYCODE"], let code = UInt16(codeText) else { return }
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
        amLog("probe: no window for synthetic key")
        return
    }
    if !NSApp.isActive {
        NSApp.activate(ignoringOtherApps: true)
    }
    window.makeKeyAndOrderFront(nil)
    let chars = env["ASTRIS_MOUSE_PROBE_CHARS"] ?? "i"
    var probeMods: NSEvent.ModifierFlags = []
    for token in (env["ASTRIS_MOUSE_PROBE_MODS"] ?? "").lowercased().split(separator: "+") {
        switch token {
        case "cmd": probeMods.insert(.command)
        case "alt": probeMods.insert(.option)
        case "ctrl": probeMods.insert(.control)
        case "shift": probeMods.insert(.shift)
        default: break
        }
    }
    func make(_ down: Bool) -> NSEvent? {
        NSEvent.keyEvent(
            with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: probeMods,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
        )
    }
    func snapshot(_ tag: String) {
        s.lock.lock()
        let line = "probe: \(tag) frontendCalls(stick=\(s.frontendStickCalls) button=\(s.frontendButtonCalls) keyboard=\(s.frontendKeyboardCalls)) keysDown=\(s.keysDown.sorted()) firstResponder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")"
        s.lock.unlock()
        amLog(line)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        amLog("probe: sending synthetic keyDown/keyUp keyCode=\(code) to \"\(window.title)\" isActive=\(NSApp.isActive) isKey=\(window.isKeyWindow)")
        snapshot("before key")
        if let down = make(true) { NSApp.sendEvent(down) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            snapshot("after keyDown")
            if let up = make(false) { NSApp.sendEvent(up) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { snapshot("after keyUp") }
        }
    }
}

private func amDiag() {
    let s = AMState.shared
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    // 按钮表偏移量只对 Astris 1.0.32 自带的 libryujinx 成立，其他版本读这个地址可能崩溃
    if version != "1.0.32" {
        amLog("diag: Astris \(version), skip button table check (offsets are for 1.0.32)")
    } else if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ryujinx_set_controller_motion_axis") {
        let slide = UInt(bitPattern: sym) &- 0x9623FC
        if let table = UnsafePointer<UInt8>(bitPattern: slide &+ 0x16217e0) {
            let len = table.withMemoryRebound(to: Int32.self, capacity: 4) { $0[2] }
            let bytes = (0..<17).map { String(table[16 + $0]) }
            amLog("diag: libryujinx button table len=\(len) map=[\(bytes.joined(separator: ","))] (expect 17 / 1,2,3,4,15,17,16,5,6,7,8,11,12,13,14,9,10)")
        }
    }
    s.lock.lock()
    let b = s.bindings
    let line = "diag: virtual=\(s.virtualHandle) physical=\(s.physical) bindings: \(b.summary)"
    let keys = b.buttons.map { "\($0.key)->\($0.value)" }.sorted().joined(separator: " ")
    let sticks = "left(up=\(b.leftStick.up ?? -1) down=\(b.leftStick.down ?? -1) left=\(b.leftStick.left ?? -1) right=\(b.leftStick.right ?? -1)) right(up=\(b.rightStick.up ?? -1) down=\(b.rightStick.down ?? -1) left=\(b.rightStick.left ?? -1) right=\(b.rightStick.right ?? -1))"
    s.lock.unlock()
    amLog(line)
    amLog("diag: \(b.player1Status)")
    amLog("diag: keyCode->button: \(keys)")
    amLog("diag: stick keys: \(sticks)")
}

// MARK: - 入口

@_cdecl("am_bootstrap")
public func amBootstrap() {
    amLog("loaded into \(ProcessInfo.processInfo.processName) pid=\(getpid())")
    if Thread.isMainThread && NSApp != nil {
        amInstall()
    }
    NotificationCenter.default.addObserver(
        forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
    ) { _ in amInstall() }
    DispatchQueue.main.async { amInstall() }
}
