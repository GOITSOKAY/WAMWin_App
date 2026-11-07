-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: RECIPES
CREATE TABLE recipe_master (
    id TEXT PRIMARY KEY,
    household_id TEXT REFERENCES household(id) ON DELETE CASCADE,
    title TEXT NOT NULL, description TEXT,
    servings REAL NOT NULL DEFAULT 2 CHECK (servings > 0),
    prep_minutes INTEGER, cook_minutes INTEGER,
    difficulty TEXT CHECK (difficulty IN ('EASY','MEDIUM','HARD')),
    cuisine_code TEXT REFERENCES cuisine(code),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    version INTEGER NOT NULL DEFAULT 1,
    created_source_code TEXT NOT NULL DEFAULT 'SYSTEM_DEFAULT' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT
) STRICT;
CREATE INDEX ix_recipe_visible ON recipe_master(household_id) WHERE deleted_at IS NULL AND is_active = 1;
CREATE TABLE recipe_meal_slot (recipe_id TEXT NOT NULL REFERENCES recipe_master(id) ON DELETE CASCADE, meal_slot TEXT NOT NULL CHECK (meal_slot IN ('BREAKFAST','LUNCH','DINNER','SNACK','DESSERT')), PRIMARY KEY (recipe_id, meal_slot)) STRICT;
CREATE TABLE recipe_ingredient (
    id TEXT PRIMARY KEY,
    recipe_id TEXT NOT NULL REFERENCES recipe_master(id) ON DELETE CASCADE,
    item_master_id TEXT NOT NULL REFERENCES item_master(id),
    quantity REAL NOT NULL CHECK (quantity > 0),
    unit_code TEXT NOT NULL REFERENCES unit_of_measure(code),
    is_optional INTEGER NOT NULL DEFAULT 0 CHECK (is_optional IN (0,1)),
    substitution_group INTEGER, preparation_note TEXT, ordinal INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX ix_ingredient_recipe ON recipe_ingredient(recipe_id);
CREATE TABLE recipe_step (recipe_id TEXT NOT NULL REFERENCES recipe_master(id) ON DELETE CASCADE, step_number INTEGER NOT NULL, instruction TEXT NOT NULL, cooking_method_code TEXT REFERENCES cooking_method(code), duration_minutes INTEGER, PRIMARY KEY (recipe_id, step_number)) STRICT;
CREATE TABLE recipe_equipment_requirement (
    id TEXT PRIMARY KEY, recipe_id TEXT NOT NULL REFERENCES recipe_master(id) ON DELETE CASCADE,
    cooking_method_code TEXT REFERENCES cooking_method(code), equipment_type_code TEXT REFERENCES equipment_type(code),
    is_optional INTEGER NOT NULL DEFAULT 0 CHECK (is_optional IN (0,1)),
    CHECK ((cooking_method_code IS NOT NULL) + (equipment_type_code IS NOT NULL) = 1)
) STRICT;
CREATE TABLE recipe_tag (recipe_id TEXT NOT NULL REFERENCES recipe_master(id) ON DELETE CASCADE, tag TEXT NOT NULL, PRIMARY KEY (recipe_id, tag)) STRICT;
