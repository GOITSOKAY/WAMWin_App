-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: CATALOG
CREATE TABLE item_master (
    id TEXT PRIMARY KEY,
    household_id TEXT REFERENCES household(id) ON DELETE CASCADE,
    item_kind TEXT NOT NULL CHECK (item_kind IN ('FOOD','BEVERAGE','INGREDIENT','CONDIMENT','SPICE','HOUSEHOLD_SUPPLY','OTHER')),
    canonical_name TEXT NOT NULL,
    display_name TEXT,
    food_category_code TEXT REFERENCES food_category(code),
    default_unit_code TEXT NOT NULL REFERENCES unit_of_measure(code),
    storage_zone TEXT NOT NULL DEFAULT 'ANY' CHECK (storage_zone IN ('AMBIENT','CHILLED','FROZEN','ANY')),
    shelf_life_ambient_days INTEGER, shelf_life_chilled_days INTEGER, shelf_life_frozen_days INTEGER, shelf_life_opened_days INTEGER,
    is_perishable INTEGER NOT NULL DEFAULT 0 CHECK (is_perishable IN (0,1)),
    is_verified INTEGER NOT NULL DEFAULT 0 CHECK (is_verified IN (0,1)),
    search_name TEXT GENERATED ALWAYS AS (lower(canonical_name)) STORED,
    created_source_code TEXT NOT NULL DEFAULT 'SYSTEM_DEFAULT' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT
) STRICT;
CREATE UNIQUE INDEX ux_item_global_name ON item_master(search_name) WHERE household_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX ux_item_household_name ON item_master(household_id, search_name) WHERE household_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX ix_item_search ON item_master(search_name);
CREATE TABLE item_alias (id TEXT PRIMARY KEY, item_master_id TEXT NOT NULL REFERENCES item_master(id) ON DELETE CASCADE, alias TEXT NOT NULL COLLATE NOCASE, locale TEXT NOT NULL DEFAULT 'en') STRICT;
CREATE INDEX ix_item_alias ON item_alias(alias);
CREATE TABLE item_allergen (item_master_id TEXT NOT NULL REFERENCES item_master(id) ON DELETE CASCADE, allergen_code TEXT NOT NULL REFERENCES allergen(code), presence TEXT NOT NULL DEFAULT 'CONTAINS' CHECK (presence IN ('CONTAINS','MAY_CONTAIN')), PRIMARY KEY (item_master_id, allergen_code)) STRICT;
CREATE TABLE item_dietary_compatibility (item_master_id TEXT NOT NULL REFERENCES item_master(id) ON DELETE CASCADE, dietary_pattern_code TEXT NOT NULL REFERENCES dietary_pattern(code), is_compatible INTEGER NOT NULL CHECK (is_compatible IN (0,1)), PRIMARY KEY (item_master_id, dietary_pattern_code)) STRICT;
CREATE TABLE item_nutrient (item_master_id TEXT NOT NULL REFERENCES item_master(id) ON DELETE CASCADE, nutrient_code TEXT NOT NULL REFERENCES nutrient(code), amount REAL NOT NULL CHECK (amount >= 0), basis TEXT NOT NULL CHECK (basis IN ('PER_100G','PER_100ML','PER_UNIT')), PRIMARY KEY (item_master_id, nutrient_code)) STRICT;
CREATE TABLE item_unit_conversion (item_master_id TEXT NOT NULL REFERENCES item_master(id) ON DELETE CASCADE, from_unit_code TEXT NOT NULL REFERENCES unit_of_measure(code), to_unit_code TEXT NOT NULL REFERENCES unit_of_measure(code), factor REAL NOT NULL CHECK (factor > 0), PRIMARY KEY (item_master_id, from_unit_code, to_unit_code)) STRICT;
