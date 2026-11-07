-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: CATALOG
CREATE TABLE unit_of_measure (
    code TEXT PRIMARY KEY, name TEXT NOT NULL, symbol TEXT NOT NULL,
    dimension TEXT NOT NULL CHECK (dimension IN ('MASS','VOLUME','COUNT','ENERGY','OTHER')),
    base_unit_code TEXT REFERENCES unit_of_measure(code),
    to_base_factor REAL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    CHECK ((base_unit_code IS NULL) = (to_base_factor IS NULL))
) STRICT;
CREATE TABLE allergen (code TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, is_major INTEGER NOT NULL DEFAULT 1) STRICT;
CREATE TABLE dietary_pattern (code TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT) STRICT;
CREATE TABLE nutrient (code TEXT PRIMARY KEY, name TEXT NOT NULL, unit_code TEXT NOT NULL REFERENCES unit_of_measure(code)) STRICT;
CREATE TABLE food_category (code TEXT PRIMARY KEY, parent_code TEXT REFERENCES food_category(code), name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0) STRICT;
CREATE TABLE cooking_method (code TEXT PRIMARY KEY, name TEXT NOT NULL, requires_heat INTEGER NOT NULL DEFAULT 1) STRICT;
CREATE TABLE cuisine (code TEXT PRIMARY KEY, name TEXT NOT NULL) STRICT;
