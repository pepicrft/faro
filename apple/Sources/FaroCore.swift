import FaroCoreFFI

/// The Rust library owns these immutable, process-lifetime strings.
enum FaroCore {
    static var name: String { field(0) }
    static var tagline: String { field(1) }
    static var status: String { field(2) }
    static var version: String { field(3) }

    private static func field(_ id: Int32) -> String {
        guard let pointer = faro_metadata_field(id),
              let value = String(validatingCString: pointer) else {
            preconditionFailure("Invalid Faro core metadata field: \(id)")
        }
        return value
    }
}
