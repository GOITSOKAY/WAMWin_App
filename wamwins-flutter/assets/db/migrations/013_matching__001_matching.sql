-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: MATCHING
CREATE TABLE match_run (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    requested_by_user_id TEXT,
    kitchen_id TEXT,
    meal_slot TEXT CHECK (meal_slot IN ('BREAKFAST','LUNCH','DINNER','SNACK','DESSERT')),
    status TEXT NOT NULL DEFAULT 'RUNNING' CHECK (status IN ('RUNNING','COMPLETED','FAILED','CANCELLED')),
    engine_version TEXT NOT NULL,
    max_results INTEGER NOT NULL DEFAULT 10 CHECK (max_results BETWEEN 1 AND 50),
    max_missing_items INTEGER NOT NULL DEFAULT 3,
    prioritize_use_soon INTEGER NOT NULL DEFAULT 1 CHECK (prioritize_use_soon IN (0,1)),
    candidate_count INTEGER, excluded_count INTEGER, duration_ms INTEGER, error_code TEXT,
    requested_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), completed_at TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    UNIQUE (id, household_id)
) STRICT;
CREATE TABLE match_run_member (
    run_id TEXT NOT NULL, household_id TEXT NOT NULL, member_id TEXT NOT NULL,
    PRIMARY KEY (run_id, member_id),
    FOREIGN KEY (run_id, household_id) REFERENCES match_run(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (member_id, household_id) REFERENCES family_member(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE TABLE match_result (
    id TEXT PRIMARY KEY, run_id TEXT NOT NULL, household_id TEXT NOT NULL,
    recipe_id TEXT NOT NULL REFERENCES recipe_master(id),
    rank INTEGER NOT NULL CHECK (rank > 0),
    total_score REAL NOT NULL,
    safety_passed INTEGER NOT NULL CHECK (safety_passed = 1),
    available_ingredient_ratio REAL NOT NULL,
    missing_item_count INTEGER NOT NULL, use_soon_item_count INTEGER NOT NULL,
    equipment_ok INTEGER NOT NULL CHECK (equipment_ok IN (0,1)),
    status TEXT NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','ACCEPTED','DISMISSED')),
    UNIQUE (id, household_id), UNIQUE (run_id, rank),
    FOREIGN KEY (run_id, household_id) REFERENCES match_run(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE TABLE match_result_factor (
    result_id TEXT NOT NULL REFERENCES match_result(id) ON DELETE CASCADE,
    factor_code TEXT NOT NULL CHECK (factor_code IN ('SAFETY','DIETARY','HEALTH_RULE','INVENTORY','EQUIPMENT','USE_SOON','PREFERENCE','PURCHASE_MINIMIZATION')),
    score REAL NOT NULL, weight REAL NOT NULL, explanation TEXT NOT NULL,
    PRIMARY KEY (result_id, factor_code)
) STRICT;
CREATE TABLE match_result_item (
    result_id TEXT NOT NULL REFERENCES match_result(id) ON DELETE CASCADE,
    item_master_id TEXT NOT NULL REFERENCES item_master(id),
    role TEXT NOT NULL CHECK (role IN ('AVAILABLE','USE_SOON','MISSING')),
    required_quantity REAL NOT NULL, unit_code TEXT NOT NULL REFERENCES unit_of_measure(code),
    PRIMARY KEY (result_id, item_master_id, role)
) STRICT;
CREATE TABLE match_exclusion (
    run_id TEXT NOT NULL REFERENCES match_run(id) ON DELETE CASCADE,
    recipe_id TEXT NOT NULL REFERENCES recipe_master(id),
    reason_code TEXT NOT NULL CHECK (reason_code IN ('ALLERGEN','INTOLERANCE','DIETARY','HEALTH_RULE','EQUIPMENT','TOO_MANY_MISSING')),
    member_id TEXT, detail TEXT,
    PRIMARY KEY (run_id, recipe_id, reason_code)
) STRICT;
