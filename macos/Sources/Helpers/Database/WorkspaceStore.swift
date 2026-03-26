import Combine
import Foundation
import GRDB

/// Combined CRUD repository for projects, workspaces, sessions, and agent launchers.
/// All database operations use GRDB's `DatabaseWriter` for concurrent read/write access.
/// Accepts either a `DatabasePool` (production) or `DatabaseQueue` (tests / in-memory).
final class WorkspaceStore: Sendable {
    private let dbPool: any DatabaseWriter

    init(dbPool: any DatabaseWriter = DatabaseManager.shared.dbPool) {
        self.dbPool = dbPool
    }

    // MARK: - Projects

    func allProjects() throws -> [ProjectRecord] {
        try dbPool.read { db in
            try ProjectRecord
                .order(ProjectRecord.Columns.sortOrder)
                .order(ProjectRecord.Columns.name)
                .fetchAll(db)
        }
    }

    func project(byId id: String) throws -> ProjectRecord {
        try dbPool.read { db in
            guard let project = try ProjectRecord.fetchOne(db, key: id) else {
                throw WorkspaceStoreError.projectNotFound(id: id)
            }
            return project
        }
    }

    func project(byRepoPath repoPath: String) throws -> ProjectRecord? {
        try dbPool.read { db in
            try ProjectRecord
                .filter(ProjectRecord.Columns.repoPath == repoPath)
                .fetchOne(db)
        }
    }

    @discardableResult
    func createProject(
        name: String,
        repoPath: String,
        icon: String? = nil,
        color: String? = nil
    ) throws -> ProjectRecord {
        try dbPool.write { db in
            var record = ProjectRecord(
                name: name,
                repoPath: repoPath,
                icon: icon,
                color: color
            )
            try record.insert(db)
            return record
        }
    }

    @discardableResult
    func updateProject(_ project: ProjectRecord) throws -> ProjectRecord {
        try dbPool.write { db in
            var record = project
            try record.update(db)
            return record
        }
    }

    func deleteProject(id: String) throws {
        try dbPool.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Workspaces

    func workspaces(forProjectId projectId: String) throws -> [WorkspaceRecord] {
        try dbPool.read { db in
            try WorkspaceRecord
                .filter(WorkspaceRecord.Columns.projectId == projectId)
                .order(WorkspaceRecord.Columns.sortOrder)
                .order(WorkspaceRecord.Columns.branch)
                .fetchAll(db)
        }
    }

    func workspace(byId id: String) throws -> WorkspaceRecord {
        try dbPool.read { db in
            guard let workspace = try WorkspaceRecord.fetchOne(db, key: id) else {
                throw WorkspaceStoreError.workspaceNotFound(id: id)
            }
            return workspace
        }
    }

    @discardableResult
    func createWorkspace(
        projectId: String,
        name: String,
        branch: String,
        worktreePath: String,
        isMainBranch: Bool = false
    ) throws -> WorkspaceRecord {
        try dbPool.write { db in
            var record = WorkspaceRecord(
                projectId: projectId,
                name: name,
                branch: branch,
                worktreePath: worktreePath,
                isMainBranch: isMainBranch
            )
            try record.insert(db)
            return record
        }
    }

    @discardableResult
    func updateWorkspace(_ workspace: WorkspaceRecord) throws -> WorkspaceRecord {
        try dbPool.write { db in
            var record = workspace
            try record.update(db)
            return record
        }
    }

    func deleteWorkspace(id: String) throws {
        try dbPool.write { db in
            _ = try WorkspaceRecord.deleteOne(db, key: id)
        }
    }

    func setActiveWorkspace(id: String) throws {
        try dbPool.write { db in
            guard var workspace = try WorkspaceRecord.fetchOne(db, key: id) else {
                throw WorkspaceStoreError.workspaceNotFound(id: id)
            }
            workspace.lastActiveAt = Date()
            try workspace.update(db)
        }
    }

    func activeWorkspaces() throws -> [(WorkspaceRecord, SessionRecord)] {
        try dbPool.read { db in
            let workspaces = try WorkspaceRecord
                .filter(WorkspaceRecord.Columns.lastActiveAt != nil)
                .order(WorkspaceRecord.Columns.lastActiveAt.desc)
                .fetchAll(db)

            return try workspaces.compactMap { workspace in
                guard let session = try SessionRecord
                    .filter(SessionRecord.Columns.workspaceId == workspace.id)
                    .filter(SessionRecord.Columns.isActive == true)
                    .fetchOne(db)
                else { return nil }
                return (workspace, session)
            }
        }
    }

    // MARK: - Sessions

    func activeSession(forWorkspaceId workspaceId: String) throws -> SessionRecord? {
        try dbPool.read { db in
            try SessionRecord
                .filter(SessionRecord.Columns.workspaceId == workspaceId)
                .filter(SessionRecord.Columns.isActive == true)
                .fetchOne(db)
        }
    }

    @discardableResult
    func saveSession(
        workspaceId: String,
        splitTreeJSON: String?,
        focusedSurfaceId: String? = nil,
        tabColor: String? = nil
    ) throws -> SessionRecord {
        try dbPool.write { db in
            // Upsert: find existing active session or create new
            if var existing = try SessionRecord
                .filter(SessionRecord.Columns.workspaceId == workspaceId)
                .filter(SessionRecord.Columns.isActive == true)
                .fetchOne(db)
            {
                existing.splitTreeJSON = splitTreeJSON
                existing.focusedSurfaceID = focusedSurfaceId
                existing.tabColor = tabColor
                try existing.update(db)
                return existing
            }

            var record = SessionRecord(
                workspaceId: workspaceId,
                splitTreeJSON: splitTreeJSON,
                focusedSurfaceID: focusedSurfaceId,
                tabColor: tabColor
            )
            try record.insert(db)
            return record
        }
    }

    func updateSession(workspaceId: String, splitTreeJSON: String?) throws {
        try dbPool.write { db in
            if var session = try SessionRecord
                .filter(SessionRecord.Columns.workspaceId == workspaceId)
                .filter(SessionRecord.Columns.isActive == true)
                .fetchOne(db)
            {
                session.splitTreeJSON = splitTreeJSON
                try session.update(db)
            }
        }
    }

    func updateSession(workspaceId: String, splitTreeJSON: String?, focusedSurfaceID: String?) throws {
        try dbPool.write { db in
            if var session = try SessionRecord
                .filter(SessionRecord.Columns.workspaceId == workspaceId)
                .filter(SessionRecord.Columns.isActive == true)
                .fetchOne(db)
            {
                session.splitTreeJSON = splitTreeJSON
                session.focusedSurfaceID = focusedSurfaceID
                try session.update(db)
            }
        }
    }

    func deleteSession(workspaceId: String) throws {
        try dbPool.write { db in
            _ = try SessionRecord
                .filter(SessionRecord.Columns.workspaceId == workspaceId)
                .deleteAll(db)
        }
    }

    func deactivateWorkspace(id: String) throws {
        try dbPool.write { db in
            let sessions = try SessionRecord
                .filter(SessionRecord.Columns.workspaceId == id)
                .filter(SessionRecord.Columns.isActive == true)
                .fetchAll(db)
            for var session in sessions {
                session.isActive = false
                try session.update(db)
            }
        }
    }

    // MARK: - Transactional Operations

    /// Imports a project with its worktrees in a single transaction.
    /// The first worktree marked `isMainWorktree` gets `isMainBranch = true`.
    @discardableResult
    func importProject(
        path: String,
        name: String,
        worktrees: [Worktree]
    ) throws -> ProjectRecord {
        try dbPool.write { db in
            var project = ProjectRecord(name: name, repoPath: path)
            try project.insert(db)

            for (index, wt) in worktrees.enumerated() {
                var workspace = WorkspaceRecord(
                    projectId: project.id,
                    name: wt.branch ?? "detached",
                    branch: wt.branch ?? "HEAD",
                    worktreePath: wt.path,
                    isMainBranch: wt.isMainWorktree,
                    sortOrder: index
                )
                try workspace.insert(db)
            }

            return project
        }
    }

    /// Overload that accepts the tuple format from WorkspaceOrchestrator.
    @discardableResult
    func importProject(
        repoPath: String,
        name: String,
        worktrees: [(branch: String, path: String, isMain: Bool)]
    ) throws -> ProjectRecord {
        try dbPool.write { db in
            var project = ProjectRecord(name: name, repoPath: repoPath)
            try project.insert(db)

            for (index, wt) in worktrees.enumerated() {
                var workspace = WorkspaceRecord(
                    projectId: project.id,
                    name: wt.branch,
                    branch: wt.branch,
                    worktreePath: wt.path,
                    isMainBranch: wt.isMain,
                    sortOrder: index
                )
                try workspace.insert(db)
            }

            return project
        }
    }

    // MARK: - Reactive Publishers (GRDB ValueObservation)

    /// Publishes all projects ordered by sortOrder, updating on any change.
    func projectsPublisher() -> AnyPublisher<[ProjectRecord], Error> {
        ValueObservation
            .tracking { db in
                try ProjectRecord
                    .order(ProjectRecord.Columns.sortOrder)
                    .order(ProjectRecord.Columns.name)
                    .fetchAll(db)
            }
            .publisher(in: dbPool, scheduling: .immediate)
            .eraseToAnyPublisher()
    }

    /// Publishes workspaces for a given project, updating on any change.
    func workspacesPublisher(forProjectId projectId: String) -> AnyPublisher<[WorkspaceRecord], Error> {
        ValueObservation
            .tracking { db in
                try WorkspaceRecord
                    .filter(WorkspaceRecord.Columns.projectId == projectId)
                    .order(WorkspaceRecord.Columns.sortOrder)
                    .order(WorkspaceRecord.Columns.branch)
                    .fetchAll(db)
            }
            .publisher(in: dbPool, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}

// MARK: - Errors

enum WorkspaceStoreError: Error, LocalizedError {
    case projectNotFound(id: String)
    case workspaceNotFound(id: String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        }
    }
}
