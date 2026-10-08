import Foundation
import TOML

struct ConfigurationFile: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumFileSize = 1_048_576

    let version: Int
    let bindings: [String: ShortcutBinding]
    let scroll: ScrollSettings

    init(bindings: [String: ShortcutBinding], scroll: ScrollSettings) {
        version = Self.currentVersion
        self.bindings = bindings
        self.scroll = scroll
    }

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Field.self)
        func check(_ keys: [Field], allowed: Set<String>, path: String) throws {
            if let unknown = keys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
                throw ConfigurationError("未知字段：\(path)\(unknown)。请检查拼写。")
            }
        }
        try check(root.allKeys, allowed: ["version", "bindings", "scroll"], path: "")
        version = try root.decode(Int.self, forKey: Field("version"))
        let scrollFields = try root.nestedContainer(keyedBy: Field.self, forKey: Field("scroll"))
        try check(scrollFields.allKeys, allowed: ["reverseVertical", "reverseHorizontal"], path: "scroll.")
        scroll = try root.decode(ScrollSettings.self, forKey: Field("scroll"))
        let inputFields = try root.nestedContainer(keyedBy: Field.self, forKey: Field("bindings"))
        var loaded: [String: ShortcutBinding] = [:]
        for input in inputFields.allKeys {
            let fields = try inputFields.nestedContainer(keyedBy: Field.self, forKey: input)
            try check(fields.allKeys, allowed: ["keyCode", "keyName", "control", "option", "shift", "command", "function"], path: "bindings.\(input.stringValue).")
            loaded[input.stringValue] = try inputFields.decode(ShortcutBinding.self, forKey: input)
        }
        bindings = loaded
    }

    static func read(from url: URL) throws -> ConfigurationFile {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileSize + 1) ?? Data()
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> ConfigurationFile {
        guard data.count <= maximumFileSize else {
            throw ConfigurationError("配置文件不能超过 1 MB。")
        }
        let configuration: ConfigurationFile
        do {
            guard let text = String(data: data, encoding: .utf8) else {
                throw ConfigurationError("配置文件必须使用 UTF-8 编码。")
            }
            configuration = try TOMLDecoder().decode(Self.self, from: text)
        } catch let error as DecodingError {
            let description: String
            switch error {
            case .keyNotFound(let key, let context):
                description = "缺少字段 " + (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                description = "字段类型不正确：" + context.codingPath.map(\.stringValue).joined(separator: ".")
            case .dataCorrupted:
                description = "TOML 内容无效，请检查配置格式。"
            @unknown default:
                description = error.localizedDescription
            }
            throw ConfigurationError(description)
        }
        try configuration.validate()
        return configuration
    }

    func write(to url: URL) throws {
        try validate()
        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var data = try encoder.encode(self)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private func validate() throws {
        guard version == Self.currentVersion else {
            throw ConfigurationError("不支持配置版本 \(version)，当前支持版本 1。")
        }
        for (inputID, shortcut) in bindings {
            let isWheel = inputID == "scroll.left" || inputID == "scroll.right"
            let isButton: Bool
            if inputID.hasPrefix("button."), let number = Int(inputID.dropFirst(7)) {
                isButton = (2...31).contains(number) && inputID == "button.\(number)"
            } else {
                isButton = false
            }
            guard isWheel || isButton else {
                throw ConfigurationError("无效鼠标输入：\(inputID)。使用 button.2～button.31、scroll.left 或 scroll.right。")
            }
            guard shortcut.keyCode <= 127 else {
                throw ConfigurationError("\(inputID) 的 keyCode 必须在 0～127 之间。")
            }
            guard !shortcut.keyName.isEmpty, shortcut.keyName.count <= 32 else {
                throw ConfigurationError("\(inputID) 的 keyName 必须为 1～32 个字符。")
            }
        }
    }
}

struct ConfigurationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
