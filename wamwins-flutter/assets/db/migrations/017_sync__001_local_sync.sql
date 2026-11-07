-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: SYNC
-- Device-side sync state. Local mutations are queued here and pushed with idempotent ids.
CREATE TABLE local_mutation_outbox (
    client_mutation_id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    module_code TEXT NOT NULL,
    entity_table TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    base_row_version INTEGER,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    pushed_at TEXT,
    result_status TEXT CHECK (result_status IN ('APPLIED','REJECTED','CONFLICT')),
    attempts INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX ix_local_outbox_pending ON local_mutation_outbox(household_id, module_code) WHERE pushed_at IS NULL;
CREATE TABLE sync_cursor (
    household_id TEXT NOT NULL,
    module_code TEXT NOT NULL,
    last_sync_version INTEGER NOT NULL DEFAULT 0,
    last_synced_at TEXT,
    PRIMARY KEY (household_id, module_code)
) STRICT;
