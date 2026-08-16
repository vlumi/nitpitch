import Foundation

/// The one JSON-through-defaults idiom every store persists with — written
/// once, so a stored property is one `decoded` in init and one `encode` in
/// its didSet.
extension UserDefaults {
    func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }
}
