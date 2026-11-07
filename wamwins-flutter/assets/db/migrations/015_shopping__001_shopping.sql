-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: SHOPPING
CREATE TABLE shopping_list (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','COMPLETED','ARCHIVED')),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id)
) STRICT;
CREATE TABLE shopping_list_item (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    shopping_list_id TEXT NOT NULL,
    item_master_id TEXT REFERENCES item_master(id),
    free_text_name TEXT,
    quantity REAL CHECK (quantity > 0),
    unit_code TEXT REFERENCES unit_of_measure(code),
    reason TEXT NOT NULL DEFAULT 'MANUAL' CHECK (reason IN ('MANUAL','LOW_STOCK','MEAL_MISSING','USE_SOON_REPLACEMENT','RECURRING')),
    source_match_result_id TEXT, source_inventory_item_id TEXT, target_storage_instance_id TEXT,
    status TEXT NOT NULL DEFAULT 'NEEDED' CHECK (status IN ('NEEDED','IN_CART','PURCHASED','SKIPPED')),
    purchased_at TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (shopping_list_id, household_id) REFERENCES shopping_list(id, household_id) ON DELETE CASCADE,
    CHECK (item_master_id IS NOT NULL OR free_text_name IS NOT NULL)
) STRICT;
CREATE INDEX ix_shopping_item_list ON shopping_list_item(shopping_list_id, status) WHERE deleted_at IS NULL;
