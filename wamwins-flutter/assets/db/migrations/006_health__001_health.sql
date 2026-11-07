-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: HEALTH
CREATE TABLE food_requirement_type (
    code TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
    nutrient_code TEXT REFERENCES nutrient(code),
    direction TEXT NOT NULL CHECK (direction IN ('LIMIT','INCREASE','AVOID','INCLUDE')),
    default_threshold REAL,
    avoid_food_category TEXT REFERENCES food_category(code)
) STRICT;

CREATE TABLE member_allergy (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    allergen_code TEXT NOT NULL REFERENCES allergen(code),
    severity TEXT NOT NULL DEFAULT 'UNKNOWN' CHECK (severity IN ('MILD','MODERATE','SEVERE','ANAPHYLACTIC','UNKNOWN')),
    notes TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE INDEX ix_member_allergy_member ON member_allergy(member_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX ux_member_allergy ON member_allergy(member_id, allergen_code) WHERE deleted_at IS NULL;
CREATE TABLE member_intolerance (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    allergen_code TEXT REFERENCES allergen(code),
    item_master_id TEXT,
    food_category_code TEXT REFERENCES food_category(code),
    severity TEXT NOT NULL DEFAULT 'MODERATE' CHECK (severity IN ('MILD','MODERATE','SEVERE')),
    handling TEXT NOT NULL DEFAULT 'EXCLUDE' CHECK (handling IN ('EXCLUDE','PENALIZE')),
    notes TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE,
    CHECK ((allergen_code IS NOT NULL) + (item_master_id IS NOT NULL) + (food_category_code IS NOT NULL) = 1)
) STRICT;
CREATE INDEX ix_member_intolerance_member ON member_intolerance(member_id) WHERE deleted_at IS NULL;
CREATE TABLE member_dietary_requirement (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    dietary_pattern_code TEXT NOT NULL REFERENCES dietary_pattern(code),
    strictness TEXT NOT NULL DEFAULT 'HARD' CHECK (strictness IN ('HARD','SOFT')),
    notes TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE INDEX ix_member_dietary_requirement_member ON member_dietary_requirement(member_id) WHERE deleted_at IS NULL;
CREATE TABLE member_health_food_requirement (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    requirement_type_code TEXT NOT NULL REFERENCES food_requirement_type(code),
    strictness TEXT NOT NULL DEFAULT 'SOFT' CHECK (strictness IN ('HARD','SOFT')),
    threshold_value REAL,
    notes TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE INDEX ix_member_health_food_requirement_member ON member_health_food_requirement(member_id) WHERE deleted_at IS NULL;
CREATE TABLE member_nutrition_target (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    nutrient_code TEXT NOT NULL REFERENCES nutrient(code),
    target_min REAL, target_max REAL,
    period TEXT NOT NULL DEFAULT 'DAY' CHECK (period IN ('MEAL','DAY','WEEK')),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE,
    CHECK (target_min IS NOT NULL OR target_max IS NOT NULL)
) STRICT;
CREATE INDEX ix_member_nutrition_target_member ON member_nutrition_target(member_id) WHERE deleted_at IS NULL;
