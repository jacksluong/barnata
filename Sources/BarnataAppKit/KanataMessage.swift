import Foundation

/// The kanata TCP messages this app sends. One JSON object per line.
public enum KanataClientMessage: Sendable, Equatable {
    case hello
    case requestLayerNames
    case requestCurrentLayerName
    case changeLayer(String)
    case reload
    case reloadNext
    case reloadPrevious

    var payload: (name: String, body: [String: String]) {
        switch self {
        case .hello: ("Hello", [:])
        case .requestLayerNames: ("RequestLayerNames", [:])
        case .requestCurrentLayerName: ("RequestCurrentLayerName", [:])
        case .changeLayer(let name): ("ChangeLayer", ["new": name])
        case .reload: ("Reload", [:])
        case .reloadNext: ("ReloadNext", [:])
        case .reloadPrevious: ("ReloadPrev", [:])
        }
    }

    public var line: String {
        let (name, body) = payload
        let fields = body.keys.sorted().map { "\"\($0)\":\(quoted(body[$0]!))" }.joined(separator: ",")
        return "{\"\(name)\":{\(fields)}}"
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// The kanata TCP messages this app reacts to. Everything else decodes to `.ignored`.
public enum KanataServerMessage: Sendable, Equatable {
    case helloOk
    case layerChange(String)
    case layerNames([String])
    case currentLayerName(String)
    case configFileReload
    case reloadResult(ok: Bool, message: String?)
    case error(String)
    case ignored(String)

    /// kanata says this when it does not understand a message, and stops answering until we reconnect
    public static let invalidMessageMarker = "you sent an invalid message"

    public var isInvalidMessageComplaint: Bool {
        guard case .error(let text) = self else { return false }
        return text.localizedCaseInsensitiveContains(KanataServerMessage.invalidMessageMarker)
    }

    public static func decode(line: String) -> KanataServerMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object.keys.first
        else { return .ignored(trimmed) }

        let body = object[name] as? [String: Any] ?? [:]

        switch name {
        case "HelloOk", "Hello":
            return .helloOk
        case "LayerChange":
            return (body["new"] as? String).map(KanataServerMessage.layerChange) ?? .ignored(name)
        case "LayerNames":
            return (body["names"] as? [String]).map(KanataServerMessage.layerNames) ?? .ignored(name)
        case "CurrentLayerName":
            return (body["name"] as? String).map(KanataServerMessage.currentLayerName) ?? .ignored(name)
        case "CurrentLayerInfo":
            return (body["name"] as? String).map(KanataServerMessage.currentLayerName) ?? .ignored(name)
        case "ConfigFileReload":
            return .configFileReload
        case "ReloadResult":
            let ok = (body["success"] as? Bool) ?? (body["status"] as? String == "Success")
            return .reloadResult(ok: ok, message: body["msg"] as? String ?? body["message"] as? String)
        case "Error":
            return .error(body["msg"] as? String ?? body["message"] as? String ?? trimmed)
        default:
            return .ignored(name)
        }
    }
}
