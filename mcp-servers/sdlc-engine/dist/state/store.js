/**
 * In-process serialization primitive used by every backend to chain
 * `transact()` calls on the same project. Independent of DB-level locks,
 * which protect against *other* processes.
 */
export class KeyedAsyncLock {
    chains = new Map();
    async acquire(key, fn) {
        const previous = this.chains.get(key) ?? Promise.resolve();
        let release;
        const current = new Promise((resolve) => {
            release = resolve;
        });
        this.chains.set(key, previous.then(() => current));
        try {
            await previous;
            return await fn();
        }
        finally {
            release();
            // Only clear if we're still the tail — otherwise a later waiter is
            // queued behind us and needs the chain to stay intact.
            if (this.chains.get(key) === current) {
                this.chains.delete(key);
            }
        }
    }
}
export function assertRevisionIncrement(current, next, projectId) {
    if (next.projectId !== projectId) {
        throw new Error(`State mutator cannot change projectId (expected ${projectId}, got ${next.projectId})`);
    }
    const expected = (current?.revision ?? 0) + 1;
    if (next.revision !== expected) {
        throw new Error(`revision must increment by exactly 1 ` +
            `(expected ${expected}, got ${next.revision})`);
    }
}
//# sourceMappingURL=store.js.map