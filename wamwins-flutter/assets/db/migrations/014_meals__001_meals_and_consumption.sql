-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: MEALS
CREATE TABLE meal_record (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT,
    recipe_id TEXT REFERENCES recipe_master(id),
    match_result_id TEXT,
    title TEXT NOT NULL,
    meal_slot TEXT CHECK (meal_slot IN ('BREAKFAST','LUNCH','DINNER','SNACK','DESSERT')),
    meal_date TEXT NOT NULL,
    servings REAL NOT NULL DEFAULT 1 CHECK (servings > 0),
    status TEXT NOT NULL DEFAULT 'PLANNED' CHECK (status IN ('PLANNED','CONFIRMED','COOKED','CANCELLED')),
    confirmed_by_user_id TEXT, confirmed_at TEXT, inventory_deducted_at TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id),
    FOREIGN KEY (match_result_id, household_id) REFERENCES match_result(id, household_id)
) STRICT;
CREATE INDEX ix_meal_household_date ON meal_record(household_id, meal_date) WHERE deleted_at IS NULL;
CREATE TABLE meal_participant (
    meal_record_id TEXT NOT NULL, household_id TEXT NOT NULL, member_id TEXT NOT NULL,
    portion_factor REAL NOT NULL DEFAULT 1 CHECK (portion_factor > 0),
    PRIMARY KEY (meal_record_id, member_id),
    FOREIGN KEY (meal_record_id, household_id) REFERENCES meal_record(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE TABLE consumption_record (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    meal_record_id TEXT, member_id TEXT,
    item_master_id TEXT NOT NULL REFERENCES item_master(id),
    quantity REAL NOT NULL CHECK (quantity > 0),
    unit_code TEXT NOT NULL REFERENCES unit_of_measure(code),
    consumed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    inventory_transaction_id TEXT REFERENCES inventory_transaction(id) ON DELETE CASCADE,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    server_sync_version INTEGER,
    FOREIGN KEY (meal_record_id, household_id) REFERENCES meal_record(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE TRIGGER trg_consumption_no_update BEFORE UPDATE ON consumption_record
BEGIN SELECT RAISE(ABORT, 'consumption_record is append-only'); END;
