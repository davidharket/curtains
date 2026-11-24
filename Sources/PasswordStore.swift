import Foundation

/// A per-user, local verifier. Only the random salt and derived key are written.
struct PasswordStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("password-v1.plist") }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("no.skjermgardin.desktop", isDirectory: true)) {
        self.directory = directory
    }

    func load() throws -> SessionPassword? {
        do {
            let record = try PropertyListDecoder().decode(SessionPassword.Verifier.self, from: Data(contentsOf: file))
            guard let password = SessionPassword(verifier: record) else { throw CocoaError(.fileReadCorruptFile) }
            return password
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func save(_ password: SessionPassword, replacing previous: SessionPassword?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            result = Result {
                guard try load()?.verifier == previous?.verifier else { throw CocoaError(.fileWriteFileExists) }
                let data = try PropertyListEncoder().encode(password.verifier)
                try data.write(to: url, options: .atomic)
            }
        }
        if let error = coordinationError { throw error }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }
}
