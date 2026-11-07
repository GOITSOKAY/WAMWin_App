-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: CONSOLIDATOR
CREATE TABLE household_summary (
    household_id TEXT PRIMARY KEY REFERENCES household(id) ON DELETE CASCADE,
    member_count INTEGER NOT NULL DEFAULT 0, kitchen_count INTEGER NOT NULL DEFAULT 0,
    storage_instance_count INTEGER NOT NULL DEFAULT 0, inventory_item_count INTEGER NOT NULL DEFAULT 0,
    use_soon_count INTEGER NOT NULL DEFAULT 0, expired_count INTEGER NOT NULL DEFAULT 0,
    low_stock_count INTEGER NOT NULL DEFAULT 0, open_shopping_item_count INTEGER NOT NULL DEFAULT 0,
    meals_last_7_days INTEGER NOT NULL DEFAULT 0, last_meal_at TEXT,
    is_stale INTEGER NOT NULL DEFAULT 0 CHECK (is_stale IN (0,1)),
    refreshed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
CREATE TABLE kitchen_summary (
    kitchen_id TEXT PRIMARY KEY REFERENCES kitchen(id) ON DELETE CASCADE,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    storage_instance_count INTEGER NOT NULL DEFAULT 0, inventory_item_count INTEGER NOT NULL DEFAULT 0,
    use_soon_count INTEGER NOT NULL DEFAULT 0, refreshed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
CREATE TABLE storage_summary (
    storage_instance_id TEXT PRIMARY KEY REFERENCES storage_instance(id) ON DELETE CASCADE,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    section_count INTEGER NOT NULL DEFAULT 0, inventory_item_count INTEGER NOT NULL DEFAULT 0,
    use_soon_count INTEGER NOT NULL DEFAULT 0, expired_count INTEGER NOT NULL DEFAULT 0,
    low_stock_count INTEGER NOT NULL DEFAULT 0, refreshed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
CREATE TABLE expiration_bucket (
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    bucket TEXT NOT NULL CHECK (bucket IN ('EXPIRED','TODAY','NEXT_3_DAYS','NEXT_7_DAYS','LATER','NO_DATE')),
    item_count INTEGER NOT NULL DEFAULT 0,
    refreshed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY (household_id, bucket)
) STRICT;
