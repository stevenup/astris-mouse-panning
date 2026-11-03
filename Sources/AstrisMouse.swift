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
    var smoothingTau = 0.005       // 一阶低通时间常数（秒），只作用于运动中的速度变化；起步、停止不经过它
    var averageEvents = 2          // 瞬时速度取最近几次鼠标事件的位移 / 实际时间跨度
    var holdTime = 0.0             // 多久没有鼠标事件就把摇杆归零（秒）；0 = 按鼠标回报间隔自适应
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
    // 鼠标键（NSEvent.buttonNumber：0 左 1 右 2 中 3/4 侧键）→ Switch 按键；只在平移开启时生效
    var mouseButtons: [Int: AMButton] = [:]

    static let mouseButtonNumbers: [(env: String, number: Int, label: String)] = [
        ("LEFT", 0, "left"), ("RIGHT", 1, "right"), ("MIDDLE", 2, "middle"), ("4", 3, "button4"), ("5", 4, "button5"),
    ]

    static func mouseButtonLabel(_ number: Int) -> String {
        mouseButtonNumbers.first { $0.number == number }?.label ?? "button\(number + 1)"
    }

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

    static func load(env: [String: String] = ProcessInfo.processInfo.environment) -> AMConfig {
        var c = AMConfig()
        func num(_ key: String) -> Double? {
            env[key].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        func flag(_ key: String) -> Bool? {
            env[key].map { ["1", "true", "yes", "on"].contains($0.lowercased()) }
        }
        if let v = num("ASTRIS_MOUSE_FULL_SPEED"), v > 0 { c.fullSpeed = v }
        if let v = num("ASTRIS_MOUSE_CURVE"), v > 0 { c.curve = v }
        if let v = num("ASTRIS_MOUSE_SMOOTHING_MS"), v >= 0 { c.smoothingTau = v / 1000 }
        if let v = num("ASTRIS_MOUSE_AVERAGE"), v >= 1, v <= 8 { c.averageEvents = Int(v) }
        if let v = num("ASTRIS_MOUSE_HOLD_MS"), v >= 0 { c.holdTime = v / 1000 }
        if env["ASTRIS_MOUSE_WINDOW_MS"] != nil {
            amLog("ASTRIS_MOUSE_WINDOW_MS 已不再使用（速度改按鼠标事件时间戳计算），忽略；停止判定见 ASTRIS_MOUSE_HOLD_MS")
        }
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
        for entry in mouseButtonNumbers {
            guard let raw = env["ASTRIS_MOUSE_BUTTON_\(entry.env)"] else { continue }
            let spec = raw.trimmingCharacters(in: .whitespaces)
            if spec.isEmpty || ["none", "off"].contains(spec.lowercased()) { continue }
            if let button = AMButton.parse(spec) {
                c.mouseButtons[entry.number] = button
            } else {
                amLog("ASTRIS_MOUSE_BUTTON_\(entry.env)=\(raw) 无法识别，可用: \(AMButton.allNames)")
            }
        }
        return c
    }

    var mouseButtonsDescription: String {
        guard !mouseButtons.isEmpty else { return "none" }
        return mouseButtons.keys.sorted().map { "\(AMConfig.mouseButtonLabel($0)):\(mouseButtons[$0]!.name)" }.joined(separator: ",")
    }

    // 解析 config.env 文本：支持 `export KEY=VALUE`、引号、行尾注释；只认 ASTRIS_MOUSE_* 键
    static func parseEnvFile(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard key.hasPrefix("ASTRIS_MOUSE_") else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                let body = value.dropFirst()
                value = String(body[..<(body.firstIndex(of: quote) ?? body.endIndex)])
            } else if let end = value.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "#" }) {
                value = String(value[..<end])
            }
            out[key] = value
        }
        return out
    }

    var holdDescription: String { holdTime > 0 ? "\(Int(holdTime * 1000))ms" : "auto" }

    var summary: String {
        "toggle=\(toggleDescription) fullSpeed=\(fullSpeed)pt/s curve=\(curve) smoothing=\(Int(smoothingTau * 1000))ms average=\(averageEvents) hold=\(holdDescription) antiDeadzone=\(antiDeadzone) outputDeadzone=\(outputDeadzone) invertY=\(invertY) mouseButtons=\(mouseButtonsDescription) controller=\(controllerOverride.map(String.init) ?? "auto") takeover=\(takeover) sound=\(sound) debug=\(debug)"
    }

    func changes(from old: AMConfig) -> [String] {
        var out: [String] = []
        func cmp<T: Equatable>(_ name: String, _ a: T, _ b: T) {
            if a != b { out.append("\(name) \(a)→\(b)") }
        }
        cmp("fullSpeed", old.fullSpeed, fullSpeed)
        cmp("curve", old.curve, curve)
        cmp("smoothingMs", Int(old.smoothingTau * 1000), Int(smoothingTau * 1000))
        cmp("average", old.averageEvents, averageEvents)
        cmp("hold", old.holdDescription, holdDescription)
        cmp("antiDeadzone", old.antiDeadzone, antiDeadzone)
        cmp("outputDeadzone", old.outputDeadzone, outputDeadzone)
        cmp("invertY", old.invertY, invertY)
        cmp("toggle", old.toggleDescription, toggleDescription)
        cmp("mouseButtons", old.mouseButtonsDescription, mouseButtonsDescription)
        cmp("controller", old.controllerOverride.map(String.init) ?? "auto", controllerOverride.map(String.init) ?? "auto")
        cmp("sound", old.sound, sound)
        cmp("debug", old.debug, debug)
        return out
    }
}

// MARK: - Astris 键位配置 → 虚拟手柄映射

// libryujinx C API 的按钮编号（内部再查表转成 GamepadButtonInputId）
enum AMButton: Int32, CaseIterable {
    case a = 0, b = 1, x = 2, y = 3, minus = 4, home = 5, plus = 6
    case leftStick = 7, rightStick = 8, l = 9, r = 10
    case dpadUp = 11, dpadDown = 12, dpadLeft = 13, dpadRight = 14, zl = 15, zr = 16

    var name: String {
        switch self {
        case .a: return "a"
        case .b: return "b"
        case .x: return "x"
        case .y: return "y"
        case .minus: return "minus"
        case .home: return "home"
        case .plus: return "plus"
        case .leftStick: return "lstick"
        case .rightStick: return "rstick"
        case .l: return "l"
        case .r: return "r"
        case .dpadUp: return "up"
        case .dpadDown: return "down"
        case .dpadLeft: return "left"
        case .dpadRight: return "right"
        case .zl: return "zl"
        case .zr: return "zr"
        }
    }

    static let allNames = AMButton.allCases.map(\.name).joined(separator: " ")

    // 用户在 config.env 里写的名字（Switch 标签）；A/B/X/Y 按 Astris 的 useNintendoLayout 换算见 AMBindings.physical
    static let aliases: [String: AMButton] = [
        "a": .a, "b": .b, "x": .x, "y": .y,
        "minus": .minus, "-": .minus, "select": .minus,
        "plus": .plus, "+": .plus, "start": .plus,
        "home": .home,
        "l": .l, "lb": .l, "l1": .l,
        "r": .r, "rb": .r, "r1": .r,
        "zl": .zl, "lt": .zl, "l2": .zl,
        "zr": .zr, "rt": .zr, "r2": .zr,
        "lstick": .leftStick, "leftstick": .leftStick, "ls": .leftStick, "l3": .leftStick,
        "rstick": .rightStick, "rightstick": .rightStick, "rs": .rightStick, "r3": .rightStick,
        "up": .dpadUp, "dpadup": .dpadUp, "dup": .dpadUp,
        "down": .dpadDown, "dpaddown": .dpadDown, "ddown": .dpadDown,
        "left": .dpadLeft, "dpadleft": .dpadLeft, "dleft": .dpadLeft,
        "right": .dpadRight, "dpadright": .dpadRight, "dright": .dpadRight,
    ]

    static func parse(_ spec: String) -> AMButton? {
        let s = spec.lowercased().trimmingCharacters(in: .whitespaces)
        if let direct = aliases[s] { return direct }
        return aliases[s.filter { !"-_ ".contains($0) }]
    }
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

// Astris 存偏好用 camelCase（playerInputConfig），交给 libryujinx 时用 snake_case（player_input_config），
// 这里按去掉下划线后不分大小写的形式查键，两种写法一视同仁
private func amKeyForm(_ key: String) -> String {
    key.lowercased().replacingOccurrences(of: "_", with: "")
}

extension Dictionary where Key == String, Value == Any {
    func amKey(_ name: String) -> String? {
        if self[name] != nil { return name }
        let want = amKeyForm(name)
        return keys.first { amKeyForm($0) == want }
    }

    subscript(am name: String) -> Any? {
        amKey(name).flatMap { self[$0] }
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

    struct Player1Location {
        let playersKey: String
        let players: [[String: Any]]
        let index: Int
        var config: [String: Any] { players[index] }
    }

    static func locatePlayer1(_ root: [String: Any]) -> Player1Location? {
        guard let key = root.amKey("playerInputConfig"),
              let players = root[key] as? [[String: Any]], !players.isEmpty
        else { return nil }
        let index = players.firstIndex { ($0[am: "playerIndex"] as? String) == "Player1" } ?? 0
        return Player1Location(playersKey: key, players: players, index: index)
    }

    static func loadFromPrefs(takeoverEnabled: Bool) -> AMBindings? {
        guard let data = UserDefaults.standard.data(forKey: "RyujinxOptions"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parse(root, source: "prefs", takeoverEnabled: takeoverEnabled)
    }

    static func load(takeoverEnabled: Bool) -> AMBindings {
        if let b = loadFromPrefs(takeoverEnabled: takeoverEnabled) { return b }
        let b = AMBindings()
        amLog("bindings: 偏好里的 RyujinxOptions 不可读，使用默认 controllerId=\"\(b.controllerId)\"，键盘映射为空")
        return b
    }

    static func parse(_ root: [String: Any], source: String, takeoverEnabled: Bool) -> AMBindings? {
        guard let p1 = locatePlayer1(root)?.config else { return nil }
        var b = AMBindings()
        b.source = source
        b.backend = (p1[am: "backend"] as? String) ?? "missing"
        let configuredId = (p1[am: "controllerId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
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
        b.useNintendoLayout = (p1[am: "useNintendoLayout"] as? Bool) ?? false

        func key(_ section: String, _ field: String) -> Int32? {
            guard let sec = p1[am: section] as? [String: Any], let name = sec[am: field] as? String else { return nil }
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

    // 需要接管时返回改写后的整份配置：Player1 → Gamepad + 虚拟手柄 id，其余字段和键名写法原样保留
    func rewrittenOptions(_ root: [String: Any]) -> [String: Any]? {
        guard takeover, let loc = AMBindings.locatePlayer1(root) else { return nil }
        var players = loc.players
        var p1 = players[loc.index]
        let sample = p1.amKey("playerIndex") ?? p1.amKey("controllerType") ?? "backend"
        p1[p1.amKey("backend") ?? AMBindings.styledKey("backend", like: sample)] = "Gamepad"
        p1[p1.amKey("controllerId") ?? AMBindings.styledKey("controllerId", like: sample)] = AMBindings.takeoverId
        players[loc.index] = p1
        var out = root
        out[loc.playersKey] = players
        return out
    }

    // 新增键时沿用同级键的写法：player_index → controller_id，PlayerIndex → ControllerId
    static func styledKey(_ camel: String, like sample: String) -> String {
        if sample.contains("_") {
            return camel.reduce(into: "") { out, ch in
                if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
            }
        }
        if let first = sample.first, first.isUppercase {
            return camel.prefix(1).uppercased() + camel.dropFirst()
        }
        return camel
    }

    // Switch 标签 → 送给 C API 的按钮：libryujinx 在 useNintendoLayout 时把 A/B、X/Y 对调
    func physical(_ button: AMButton) -> AMButton {
        guard useNintendoLayout else { return button }
        switch button {
        case .a: return .b
        case .b: return .a
        case .x: return .y
        case .y: return .x
        default: return button
        }
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
    // 主线程直接读写；其他线程读取时先拿 lock 拷一份
    var cfg: AMConfig
    var bindings: AMBindings

    // config.env 热更新：首次收到文件内容时，把启动环境里不是来自文件的键记为命令行临时覆盖
    var configSource: DispatchSourceRead?
    var configPending = Data()
    var inlineEnv: [String: String]?

    private init() {
        cfg = AMConfig.load()
        bindings = AMBindings.load(takeoverEnabled: cfg.takeover)
    }

    func snapshotConfig() -> AMConfig {
        lock.lock()
        defer { lock.unlock() }
        return cfg
    }

    var installed = false
    var active = false
    var virtualHandle: Int32 = -1
    var physical: [String: Int32] = [:]
    var keysDown = Set<Int32>()
    var toggleKeyDown = false
    var connectFailureLogged = false
    var optionsShapeLogged = false
    var mouseHeld = Set<Int>()      // 平移中被我们吞掉 mouseDown 的鼠标键号

    var frontendRight: (x: Float, y: Float) = (0, 0)
    var events: [(t: Double, dx: Double, dy: Double)] = []   // 最近 100ms 内的鼠标位移，t 为事件时间戳
    var velocity: (x: Double, y: Double) = (0, 0)             // 最近一次事件估出的瞬时速度 pt/s
    var holdUntil: Double = 0                                 // 过了这个时刻还没新事件就视为鼠标已停
    var holdTimer: DispatchSourceTimer?
    var filtered: (x: Double, y: Double) = (0, 0)
    var lastUpdate: Double = 0
    var lastSent: (x: Float, y: Float) = (0, 0)
    var startTime: Double = 0
    var eventOffsetLogged = false
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

    // 键盘键只转发给虚拟手柄；鼠标键发往真手柄时不能把键盘状态算进去，否则松开鼠标后按钮会卡住
    var mouseTargetKeys: Set<Int32> { handle == virtualHandle ? keysDown : [] }
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
        amPushInputState()
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
    // 偏好暂时不可读时保持现状，不要退回默认值引起虚拟手柄反复拔插
    guard let fresh = AMBindings.loadFromPrefs(takeoverEnabled: s.cfg.takeover) else { return }
    amApplyBindings(fresh)
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
    amPushInputState()
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
    let cfg = s.snapshotConfig()
    let data = Data(bytes: json, count: strlen(json))
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        amLog("options: 前端传给 libryujinx 的 JSON 无法解析，原样放行")
        return nil
    }
    guard let loc = AMBindings.locatePlayer1(root),
          let fresh = AMBindings.parse(root, source: "update_options", takeoverEnabled: cfg.takeover)
    else {
        amLog("options: 前端传给 libryujinx 的 JSON 里找不到玩家输入配置，原样放行；顶层键: \(root.keys.sorted().prefix(15).joined(separator: ","))")
        return nil
    }
    s.lock.lock()
    let firstTime = !s.optionsShapeLogged
    s.optionsShapeLogged = true
    s.lock.unlock()
    if firstTime {
        amLog("options: libryujinx 收到的 Player1 键名: \(loc.config.keys.sorted().joined(separator: ","))")
    }
    amApplyBindings(fresh)
    guard let patched = fresh.rewrittenOptions(root),
          let out = try? JSONSerialization.data(withJSONObject: patched, options: [.withoutEscapingSlashes]),
          let text = String(data: out, encoding: .utf8)
    else { return nil }
    if firstTime || cfg.debug {
        let p1 = AMBindings.locatePlayer1(patched)?.config ?? [:]
        amLog("options: Player1 rewritten (\(data.count) -> \(out.count) bytes): \(p1.amKey("backend") ?? "backend")=\(p1[am: "backend"] ?? "?") \(p1.amKey("controllerId") ?? "controllerId")=\(p1[am: "controllerId"] ?? "?")")
    }
    return strdup(text)
}

// MARK: - 键盘 / 鼠标键 → 虚拟手柄

// 同一个手柄按钮可能同时被键盘键和鼠标键绑定，任一按着就算按下
private func amButtonState(_ button: AMButton, cfg: AMConfig, bindings: AMBindings,
                           keysDown: Set<Int32>, mouseHeld: Set<Int>) -> Int32 {
    if keysDown.contains(where: { bindings.buttons[$0] == button }) { return 1 }
    if mouseHeld.contains(where: { cfg.mouseButtons[$0].map(bindings.physical) == button }) { return 1 }
    return 0
}

private func amPushInputState() {
    let s = AMState.shared
    s.lock.lock()
    let h = s.virtualHandle
    let cfg = s.cfg
    let b = s.bindings
    let keys = s.keysDown
    let mouse = s.mouseHeld
    let active = s.active
    s.lock.unlock()
    guard h >= 0 else { return }
    let buttons = Set(b.buttons.values).union(cfg.mouseButtons.values.map(b.physical))
    for button in buttons {
        ryujinx_set_controller_button_pressed(
            h, button.rawValue, amButtonState(button, cfg: cfg, bindings: b, keysDown: keys, mouseHeld: mouse))
    }
    let left = b.leftStick.value(keys)
    ryujinx_set_controller_stick_axis(h, 0, left.x, left.y)
    if !active {
        let right = b.rightStick.value(keys)
        ryujinx_set_controller_stick_axis(h, 1, right.x, right.y)
    }
}

// MARK: - 鼠标键 → 手柄按钮（主线程）

// 平移开启时，绑定了的鼠标键按下/抬起转成手柄按钮并吞掉事件；没绑定的照常交给 Astris。
// 抬起只吞我们吞过按下的那一次，避免 Astris 收到有头无尾的点击。
private func amHandleMouseButton(_ event: NSEvent) -> NSEvent? {
    let s = AMState.shared
    let number = Int(event.buttonNumber)
    let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown
    let cfg = s.cfg

    if isDown {
        guard s.active, let bound = cfg.mouseButtons[number] else { return event }
        s.lock.lock()
        s.mouseHeld.insert(number)
        s.lock.unlock()
        amSendMouseButton(number, bound, down: true)
        return nil
    }

    s.lock.lock()
    let swallowed = s.mouseHeld.remove(number) != nil
    s.lock.unlock()
    guard swallowed else { return event }
    if let bound = cfg.mouseButtons[number] {
        amSendMouseButton(number, bound, down: false)
    }
    return nil
}

private func amSendMouseButton(_ number: Int, _ bound: AMButton, down: Bool) {
    let s = AMState.shared
    s.lock.lock()
    let handle = s.handle
    let cfg = s.cfg
    let b = s.bindings
    let keys = s.mouseTargetKeys
    let mouse = s.mouseHeld
    s.lock.unlock()
    guard let handle else { return }
    let button = b.physical(bound)
    let state = amButtonState(button, cfg: cfg, bindings: b, keysDown: keys, mouseHeld: mouse)
    ryujinx_set_controller_button_pressed(handle, button.rawValue, state)
    if cfg.debug {
        amLog("mouse \(AMConfig.mouseButtonLabel(number)) \(down ? "down" : "up") -> \(bound.name)\(button == bound ? "" : "(\(button.name))") pressed=\(state) controller \(handle)")
    }
}

// 绑定热更新时，正按着的鼠标键：旧按钮按新状态重算（通常是松开），新按钮按下
private func amResyncMouseButtons(previous old: AMConfig) {
    let s = AMState.shared
    s.lock.lock()
    let handle = s.handle
    let cfg = s.cfg
    let b = s.bindings
    let keys = s.mouseTargetKeys
    let mouse = s.mouseHeld
    s.lock.unlock()
    guard let handle, !mouse.isEmpty else { return }
    var affected = Set<AMButton>()
    for number in mouse {
        if let o = old.mouseButtons[number] { affected.insert(b.physical(o)) }
        if let n = cfg.mouseButtons[number] { affected.insert(b.physical(n)) }
    }
    for button in affected {
        let state = amButtonState(button, cfg: cfg, bindings: b, keysDown: keys, mouseHeld: mouse)
        ryujinx_set_controller_button_pressed(handle, button.rawValue, state)
        if cfg.debug { amLog("mouse rebind -> \(button.name) pressed=\(state) controller \(handle)") }
    }
}

// 平移停止时松开鼠标按着的手柄按钮：之后的 mouseUp 会直接交给 Astris，收不到也不会卡住
private func amReleaseMouseButtons() {
    let s = AMState.shared
    s.lock.lock()
    let held = s.mouseHeld
    s.mouseHeld.removeAll()
    let handle = s.handle
    let cfg = s.cfg
    let b = s.bindings
    let keys = s.mouseTargetKeys
    s.lock.unlock()
    guard let handle, !held.isEmpty else { return }
    for number in held {
        guard let bound = cfg.mouseButtons[number] else { continue }
        let button = b.physical(bound)
        let state = amButtonState(button, cfg: cfg, bindings: b, keysDown: keys, mouseHeld: [])
        ryujinx_set_controller_button_pressed(handle, button.rawValue, state)
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
    let cfg = s.snapshotConfig()
    if key == Int32(cfg.toggleKeyCode) {
        if pressed != 0 {
            if amCurrentModifiers(forKey: key) == cfg.toggleModifiers {
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
    let mouse = s.mouseHeld
    let active = s.active
    let debug = cfg.debug
    s.lock.unlock()
    if debug {
        amLog("frontend keyboard_key_pressed(key=\(key), pressed=\(pressed))")
    }
    guard h >= 0 else { return false }
    if let button = b.buttons[key] {
        let state = amButtonState(button, cfg: cfg, bindings: b, keysDown: keys, mouseHeld: mouse)
        ryujinx_set_controller_button_pressed(h, button.rawValue, state)
        if debug { amLog("emu button \(button.name) pressed=\(state) -> controller \(h)") }
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
        amTick()
    }
}

func amInstall() {
    let s = AMState.shared
    guard !s.installed else { return }
    s.installed = true

    if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: { event in
        let cfg = AMState.shared.cfg
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
            amAccumulate(event)
            return nil
        }
    ) {
        s.monitors.append(m)
    }

    if let m = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp],
        handler: { event in amHandleMouseButton(event) }
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
    amInstallConfigWatcher()

    amLog("installed: \(s.cfg.summary)")
    amLog("bindings: \(s.bindings.summary)")
    amLog(s.bindings.player1Status)
}

// MARK: - config.env 热更新（文件由 astris-launch 监视，内容经管道送进来；见 launcher.c）

private func amInstallConfigWatcher() {
    let env = ProcessInfo.processInfo.environment
    guard let fdText = env["ASTRIS_MOUSE_CONFIG_FD"], let fd = Int32(fdText) else { return }
    let path = env["ASTRIS_MOUSE_CONFIG_FILE"] ?? "config.env"
    _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

    let s = AMState.shared
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    source.setEventHandler {
        var chunk = [UInt8](repeating: 0, count: 16384)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n > 0 { s.configPending.append(chunk, count: n); continue }
            if n == 0 {
                amLog("config: watcher pipe closed, live reload off")
                s.configSource?.cancel()
                s.configSource = nil
                return
            }
            if errno == EINTR { continue }
            break
        }
        // 帧：4 字节大端长度 + 内容
        while s.configPending.count >= 4 {
            let length = s.configPending.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard s.configPending.count >= 4 + length else { break }
            let body = s.configPending.subdata(in: 4..<(4 + length))
            s.configPending.removeSubrange(0..<(4 + length))
            amApplyConfigFile(String(decoding: body, as: UTF8.self), path: path)
        }
    }
    source.resume()
    s.configSource = source
}

private func amApplyConfigFile(_ text: String, path: String) {
    let s = AMState.shared
    let file = AMConfig.parseEnvFile(text)
    let firstTime = s.inlineEnv == nil
    if firstTime {
        // 第一帧就是启动时的文件；启动环境里与之不符的键来自命令行前缀（如 ASTRIS_MOUSE_DEBUG=1 ./run.sh），
        // 之后一直保留，文件里有同名键时以文件为准（和 run.sh 里 source 的先后顺序一致）
        let launch = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("ASTRIS_MOUSE_") }
        s.inlineEnv = launch.filter { file[$0.key] != $0.value }
    }
    var merged = s.inlineEnv ?? [:]
    for (k, v) in file { merged[k] = v }
    var fresh = AMConfig.load(env: merged)
    let requestedTakeover = fresh.takeover

    s.lock.lock()
    let old = s.cfg
    fresh.takeover = old.takeover
    s.cfg = fresh
    s.lock.unlock()

    if requestedTakeover != old.takeover {
        amLog("config: ASTRIS_MOUSE_TAKEOVER 只在启动时生效，本次沿用 \(old.takeover)，重启后按新值")
    }
    if fresh.mouseButtons != old.mouseButtons {
        amResyncMouseButtons(previous: old)
    }
    let changes = fresh.changes(from: old)
    let name = (path as NSString).lastPathComponent
    if firstTime {
        amLog("config: live reload on, watching \(path)" + (changes.isEmpty ? "" : "; " + changes.joined(separator: ", ")))
    } else if changes.isEmpty {
        amLog("config: \(name) reloaded, no effective changes")
    } else {
        amLog("config: \(name) applied: \(changes.joined(separator: ", "))")
    }
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
    s.events.removeAll()
    s.velocity = (0, 0)
    s.holdUntil = 0
    s.filtered = (0, 0)
    s.lastUpdate = 0
    s.lastSent = (0, 0)
    s.frontendRight = (0, 0)
    s.moves = 0
    s.sends = 0
    s.swallowed = 0
    s.startTime = CACurrentMediaTime()
    s.eventOffsetLogged = false
    s.active = true
    s.lock.unlock()

    let link = window.displayLink(target: AMTicker.shared, selector: #selector(AMTicker.tick(_:)))
    link.add(to: .main, forMode: .common)
    s.displayLink = link
    s.holdTimer = amMakeHoldTimer()

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
    s.holdTimer?.cancel()
    s.holdTimer = nil

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
    amReleaseMouseButtons()

    if s.cfg.sound { NSSound(named: "Pop")?.play() }
    amLog("panning OFF (\(reason)) moves=\(stats.0) sends=\(stats.1) swallowedFrontend=\(stats.2)")
}

// MARK: - 采样与输出

private let amFirstEventSpread = 0.016     // 静止后第一个事件没有前一个事件可算速度：把这段位移摊在接下来 16ms 上输出
private let amRestGap = 0.050              // 两次事件相隔超过这个值就当作重新起步
private let amMergeGap = 0.0005            // 时间戳几乎相同的事件并成一个

// 每个鼠标事件：用事件时间戳算瞬时速度，立刻输出；再定一个"没有下一个事件就归零"的时限。
// 速度 = 最近 averageEvents 次位移之和 / 这段实际跨度，所以起步第二个事件起就是真实速度，不像固定窗口要慢慢填满。
private func amAccumulate(_ event: NSEvent) {
    let s = AMState.shared
    let cfg = s.cfg
    let now = CACurrentMediaTime()
    var t = event.timestamp
    if abs(t - now) > 1 { t = now }     // 时间基对不上就退回到达时间
    let dx = Double(event.deltaX), dy = Double(event.deltaY)

    s.lock.lock()
    // 刚 warp 过的前 60ms 内 delta 不可信，丢弃
    guard s.active, now - s.startTime > 0.06 else { s.lock.unlock(); return }
    s.moves += 1
    if cfg.debug && !s.eventOffsetLogged {
        s.eventOffsetLogged = true
        amLog(String(format: "mouse event delivery latency %.1fms (timestamp→arrival)", (now - t) * 1000))
    }

    if let last = s.events.last, t - last.t < amMergeGap {
        s.events[s.events.count - 1].dx += dx
        s.events[s.events.count - 1].dy += dy
    } else {
        s.events.append((t, dx, dy))
    }
    s.events.removeAll { $0.t < t - 0.1 }
    let events = s.events
    let n = events.count
    let last = events[n - 1]

    let hold: Double
    if n == 1 || last.t - events[n - 2].t > amRestGap {
        // 起步：先按"位移摊在 16ms 上"输出，第二个事件一到就是真实速度；这样轻推一下不会过冲
        s.velocity = (last.dx / amFirstEventSpread, last.dy / amFirstEventSpread)
        hold = cfg.holdTime > 0 ? cfg.holdTime : amFirstEventSpread
    } else {
        let interval = last.t - events[n - 2].t
        var sumX = last.dx, sumY = last.dy
        var anchor = n - 2
        var used = 1
        while used < cfg.averageEvents, anchor > 0, events[anchor].t - events[anchor - 1].t <= amRestGap {
            sumX += events[anchor].dx
            sumY += events[anchor].dy
            anchor -= 1
            used += 1
        }
        let span = last.t - events[anchor].t
        s.velocity = (sumX / span, sumY / span)
        // 下一个事件应在约一个间隔后到；多等半个间隔加 4ms 抖动余量还没来，就是停了
        hold = cfg.holdTime > 0 ? cfg.holdTime : min(max(interval * 1.5 + 0.004, 0.012), 0.060)
    }
    s.holdUntil = t + hold
    s.lock.unlock()

    // 时限一到就归零，不等下一帧
    s.holdTimer?.schedule(deadline: .now() + max(hold - (now - t), 0) + 0.0005, leeway: .microseconds(100))

    amUpdate(now: now)
}

// Timer / 普通 GCD 定时器会被系统合并推迟 5–9ms，停止会明显拖后，所以用 strict
func amMakeHoldTimer() -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
    timer.schedule(deadline: .distantFuture)
    timer.setEventHandler { amUpdate(now: CACurrentMediaTime()) }
    timer.resume()
    return timer
}

private func amTick() {
    let s = AMState.shared
    let now = CACurrentMediaTime()
    guard s.active else { return }
    amUpdate(now: now)

    // Astris 自己的 hide/unhide 可能把光标放出来；周期性补一次 hide，计数在 stop 时成对归还
    if now - s.lastCursorCheck > 2.0 {
        s.lastCursorCheck = now
        if NSApp.isActive && s.hideCount < 3 {
            NSCursor.hide()
            s.hideCount += 1
        }
    }
}

// 当前速度 → 摇杆值并发送。起步直接跳到目标值、停止直接归零，低通只平滑运动中的速度变化。
private func amUpdate(now: Double) {
    let s = AMState.shared
    let cfg = s.cfg

    s.lock.lock()
    guard s.active else { s.lock.unlock(); return }
    let velocity = now < s.holdUntil ? s.velocity : (0.0, 0.0)
    let frontend = s.frontendRight
    s.lock.unlock()

    // 速度 → 目标摇杆向量（y 轴向上为正；Cocoa deltaY 向下为正）
    var targetX = velocity.0 / cfg.fullSpeed
    var targetY = -velocity.1 / cfg.fullSpeed
    if cfg.invertY { targetY = -targetY }
    let targetMag = (targetX * targetX + targetY * targetY).squareRoot()
    if targetMag > 0 {
        let shaped = pow(min(targetMag, 1.0), cfg.curve)
        targetX *= shaped / targetMag
        targetY *= shaped / targetMag
    }

    let dt = s.lastUpdate > 0 ? now - s.lastUpdate : 0
    s.lastUpdate = now
    let wasStill = s.filtered.x == 0 && s.filtered.y == 0
    if targetMag == 0 || wasStill || cfg.smoothingTau <= 0 {
        s.filtered = (targetX, targetY)
    } else {
        let alpha = 1 - exp(-dt / cfg.smoothingTau)
        s.filtered.x += (targetX - s.filtered.x) * alpha
        s.filtered.y += (targetY - s.filtered.y) * alpha
    }
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
}

private func amSend(_ v: (x: Float, y: Float)) {
    let s = AMState.shared
    if v.x == 0 && v.y == 0 && s.lastSent.x == 0 && s.lastSent.y == 0 { return }
    guard let handle = s.handle else { return }
    ryujinx_set_controller_stick_axis(handle, 1, v.x, v.y)
    s.lastSent = v
    s.sends += 1
    if s.cfg.debug && s.sends % 30 == 0 {
        amLog("send stick_axis(controller=\(handle), stick=1, x=\(v.x), y=\(v.y)) velocity=(\(Int(s.velocity.x)), \(Int(s.velocity.y)))pt/s events=\(s.events.count)")
    }
}

// MARK: - 诊断（notifyutil -p dev.astrismouse.probe / .diag）

private func amProbe() {
    let s = AMState.shared
    s.lock.lock()
    let summary = "probe: active=\(s.active) controller=\(s.handle.map(String.init) ?? "none") virtual=\(s.virtualHandle) physical=\(s.physical) keysDown=\(s.keysDown.sorted()) mouseHeld=\(s.mouseHeld.sorted()) frontendRight=\(s.frontendRight) frontendCalls(stick=\(s.frontendStickCalls) button=\(s.frontendButtonCalls) keyboard=\(s.frontendKeyboardCalls)) moves=\(s.moves) sends=\(s.sends) swallowed=\(s.swallowed)"
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
    amLog("diag: mouse buttons: \(s.cfg.mouseButtonsDescription)\(b.useNintendoLayout ? " (nintendo layout: a/b, x/y swapped on send)" : "")")
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
