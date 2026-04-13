import Database from "better-sqlite3";
import { KeyedAsyncLock, assertRevisionIncrement, } from "./store.js";
import { parseConsensusStatus } from "../consensus.js";
export class SqliteStateStore {
    db;
    locks = new KeyedAsyncLock();
    constructor(filename) {
        this.db = new Database(filename);
        this.db.pragma("journal_mode = WAL");
        this.db.pragma("synchronous = NORMAL");
        this.db.pragma("busy_timeout = 5000");
        this.db.pragma("foreign_keys = ON");
    }
    async init() {
        this.db.exec(`
      CREATE TABLE IF NOT EXISTS project_state (
        project_id TEXT PRIMARY KEY,
        current_phase TEXT NOT NULL,
        satisfied_criteria TEXT NOT NULL,
        last_consensus TEXT,
        updated_at TEXT NOT NULL,
        revision INTEGER NOT NULL
      );
    `);
    }
    async read(projectId) {
        const row = this.db
            .prepare("SELECT * FROM project_state WHERE project_id = ?")
            .get(projectId);
        return row ? rowToState(row) : null;
    }
    async transact(projectId, mutator) {
        return this.locks.acquire(projectId, () => Promise.resolve(this.runTransaction(projectId, mutator)));
    }
    runTransaction(projectId, mutator) {
        // better-sqlite3's `db.transaction()` helper gives us a proper
        // BEGIN/COMMIT/ROLLBACK with automatic rollback on throw, and
        // uses BEGIN IMMEDIATE via the "immediate" mode — preventing
        // another writer from sneaking in between our SELECT and UPDATE.
        const run = this.db.transaction(() => {
            const row = this.db
                .prepare("SELECT * FROM project_state WHERE project_id = ?")
                .get(projectId);
            const current = row ? rowToState(row) : null;
            const { next, result } = mutator(current);
            assertRevisionIncrement(current, next, projectId);
            if (current === null) {
                this.db
                    .prepare(`INSERT INTO project_state
               (project_id, current_phase, satisfied_criteria, last_consensus, updated_at, revision)
             VALUES (?, ?, ?, ?, ?, ?)`)
                    .run(next.projectId, next.currentPhase, JSON.stringify(next.satisfiedCriteria), next.lastConsensus ? JSON.stringify(next.lastConsensus) : null, next.updatedAt, next.revision);
            }
            else {
                const update = this.db
                    .prepare(`UPDATE project_state
               SET current_phase = ?,
                   satisfied_criteria = ?,
                   last_consensus = ?,
                   updated_at = ?,
                   revision = ?
             WHERE project_id = ? AND revision = ?`)
                    .run(next.currentPhase, JSON.stringify(next.satisfiedCriteria), next.lastConsensus ? JSON.stringify(next.lastConsensus) : null, next.updatedAt, next.revision, next.projectId, current.revision);
                if (update.changes !== 1) {
                    throw new Error(`Optimistic lock failed for project ${projectId}: ` +
                        `expected revision ${current.revision}`);
                }
            }
            return result;
        });
        return run.immediate();
    }
    async close() {
        this.db.close();
    }
}
function rowToState(row) {
    return {
        projectId: row.project_id,
        currentPhase: row.current_phase,
        satisfiedCriteria: JSON.parse(row.satisfied_criteria),
        lastConsensus: row.last_consensus
            ? parseConsensusRow(JSON.parse(row.last_consensus))
            : null,
        updatedAt: row.updated_at,
        revision: row.revision,
    };
}
function parseConsensusRow(raw) {
    if (!raw || typeof raw !== "object") {
        throw new Error("Corrupt consensus record in database");
    }
    const r = raw;
    return {
        phase: r.phase,
        status: parseConsensusStatus(r.status),
        agreement: Number(r.agreement),
        criticalIssues: Number(r.criticalIssues),
        recordedAt: String(r.recordedAt),
    };
}
//# sourceMappingURL=sqlite.js.map