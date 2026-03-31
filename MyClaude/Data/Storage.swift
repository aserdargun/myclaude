import Foundation

protocol StorageProtocol {
    func save<T: Encodable>(_ value: T, forKey key: String)
    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T?
    func remove(forKey key: String)
}

final class UserDefaultsStorage: StorageProtocol {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try encoder.encode(value)
            defaults.set(data, forKey: key)
        } catch {
            print("Storage: failed to encode \(key): \(error)")
        }
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
