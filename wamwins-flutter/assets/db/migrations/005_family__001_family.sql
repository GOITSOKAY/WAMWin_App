-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: FAMILY
CREATE TABLE family_member (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    linked_user_id TEXT REFERENCES user_account(id) ON DELETE SET NULL,
    display_name TEXT NOT NULL,
    relationship TEXT CHECK (relationship IN ('SELF','PARTNER','CHILD','PARENT','SIBLING','GRANDPARENT','RELATIVE','CAREGIVER','GUEST','OTHER')),
    birth_date TEXT,
    age_band TEXT CHECK (age_band IN ('INFANT','TODDLER','CHILD','TEEN','ADULT','SENIOR')),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    include_in_matching_by_default INTEGER NOT NULL DEFAULT 1 CHECK (include_in_matching_by_default IN (0,1)),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (provenance_id, household_id) REFERENCES record_provenance(id, household_id)
) STRICT;
CREATE INDEX ix_member_household ON family_member(household_id) WHERE deleted_at IS NULL;

CREATE TABLE member_preference (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    preference_kind TEXT NOT NULL CHECK (preference_kind IN ('FAVORITE','LIKE','DISLIKE','AVOID')),
    subject_type TEXT NOT NULL CHECK (subject_type IN ('ITEM','FOOD_CATEGORY','CUISINE','RECIPE','COOKING_METHOD')),
    item_master_id TEXT,
    food_category_code TEXT REFERENCES food_category(code),
    cuisine_code TEXT REFERENCES cuisine(code),
    recipe_id TEXT,
    cooking_method_code TEXT REFERENCES cooking_method(code),
    strength INTEGER NOT NULL DEFAULT 3 CHECK (strength BETWEEN 1 AND 5),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE,
    CHECK ((item_master_id IS NOT NULL) + (food_category_code IS NOT NULL) + (cuisine_code IS NOT NULL) + (recipe_id IS NOT NULL) + (cooking_method_code IS NOT NULL) = 1)
) STRICT;
CREATE INDEX ix_preference_member ON member_preference(member_id) WHERE deleted_at IS NULL;
