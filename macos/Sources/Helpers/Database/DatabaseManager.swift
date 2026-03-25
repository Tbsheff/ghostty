import Foundation
import GRDB
import os

/// Singleton managing the SQLite database for workspace persistence.
/// Uses GRDB's DatabasePool with WAL mode for concurrent read/write access.
final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    /// The database pool. Available after `setup()` is called.
    private let _dbPool: OSAllocatedUnfairLock<DatabasePool?> = .init(initialState: nil)

    var dbPool: DatabasePool {
        guard let pool = _dbPool.withLock({ $0 }) else {
            fatalError("DatabaseManager.setup() must be called before accessing dbPool")
        }
        return pool
    }

    private init() {}

    /// Initialize the database. Call once from AppDelegate on launch.
    func setup() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Ghostty", isDirectory: true)

        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let dbPath = appSupport.appendingPathComponent("workspaces.db").path

        var config = Configuration()
        config.prepareDatabase { db in
            // WAL mode for concurrent readers + single writer
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Enable foreign key enforcement
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let pool = try DatabasePool(path: dbPath, configuration: config)
        _dbPool.withLock { $0 = pool }

        try migrator.migrate(pool)
    }

    /// All database migrations, applied in order.
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Wipe and recreate DB on schema change during development
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        Migration001_InitialSchema.register(in: &migrator)

        return migrator
    }
}
