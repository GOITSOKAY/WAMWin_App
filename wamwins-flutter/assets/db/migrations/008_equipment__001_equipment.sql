-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: EQUIPMENT
CREATE TABLE equipment_type (
    code TEXT PRIMARY KEY,
    equipment_class TEXT NOT NULL CHECK (equipment_class IN ('APPLIANCE','UTENSIL','COOKWARE','CONTAINER')),
    name TEXT NOT NULL,
    category TEXT,
    provides_storage_type_code TEXT REFERENCES storage_type(code),
    sort_order INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    UNIQUE (code, equipment_class)
) STRICT;
CREATE TABLE equipment_type_cooking_method (
    equipment_type_code TEXT NOT NULL REFERENCES equipment_type(code) ON DELETE CASCADE,
    cooking_method_code TEXT NOT NULL REFERENCES cooking_method(code),
    PRIMARY KEY (equipment_type_code, cooking_method_code)
) STRICT;

CREATE TABLE household_appliance (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    equipment_type_code TEXT NOT NULL,
    equipment_class TEXT NOT NULL DEFAULT 'APPLIANCE' CHECK (equipment_class = 'APPLIANCE'),
    name TEXT NOT NULL,
    brand TEXT, model TEXT, capacity_value REAL, capacity_unit_code TEXT REFERENCES unit_of_measure(code), condition TEXT NOT NULL DEFAULT 'WORKING' CHECK (condition IN ('WORKING','NEEDS_REPAIR','OUT_OF_SERVICE')), notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (equipment_type_code, equipment_class) REFERENCES equipment_type(code, equipment_class)
) STRICT;
CREATE INDEX ix_household_appliance_kitchen ON household_appliance(kitchen_id) WHERE deleted_at IS NULL;
CREATE TABLE household_utensil (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    equipment_type_code TEXT NOT NULL,
    equipment_class TEXT NOT NULL DEFAULT 'UTENSIL' CHECK (equipment_class = 'UTENSIL'),
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0), condition TEXT NOT NULL DEFAULT 'WORKING' CHECK (condition IN ('WORKING','NEEDS_REPAIR','OUT_OF_SERVICE')), notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (equipment_type_code, equipment_class) REFERENCES equipment_type(code, equipment_class)
) STRICT;
CREATE INDEX ix_household_utensil_kitchen ON household_utensil(kitchen_id) WHERE deleted_at IS NULL;
CREATE TABLE household_cookware (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    equipment_type_code TEXT NOT NULL,
    equipment_class TEXT NOT NULL DEFAULT 'COOKWARE' CHECK (equipment_class = 'COOKWARE'),
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0), size_value REAL, size_unit_code TEXT REFERENCES unit_of_measure(code), material TEXT, condition TEXT NOT NULL DEFAULT 'WORKING' CHECK (condition IN ('WORKING','NEEDS_REPAIR','OUT_OF_SERVICE')), notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (equipment_type_code, equipment_class) REFERENCES equipment_type(code, equipment_class)
) STRICT;
CREATE INDEX ix_household_cookware_kitchen ON household_cookware(kitchen_id) WHERE deleted_at IS NULL;
CREATE TABLE household_container (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    storage_instance_id TEXT,
    storage_section_id TEXT,
    equipment_type_code TEXT NOT NULL,
    equipment_class TEXT NOT NULL DEFAULT 'CONTAINER' CHECK (equipment_class = 'CONTAINER'),
    name TEXT NOT NULL,
    label TEXT, capacity_value REAL, capacity_unit_code TEXT REFERENCES unit_of_measure(code), is_airtight INTEGER,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (equipment_type_code, equipment_class) REFERENCES equipment_type(code, equipment_class)
) STRICT;
CREATE INDEX ix_household_container_kitchen ON household_container(kitchen_id) WHERE deleted_at IS NULL;
CREATE VIEW v_household_cooking_capability AS
SELECT e.household_id, e.kitchen_id, m.cooking_method_code, COUNT(*) AS equipment_count
  FROM (SELECT household_id, kitchen_id, equipment_type_code FROM household_appliance WHERE deleted_at IS NULL AND is_active = 1 AND condition = 'WORKING'
        UNION ALL SELECT household_id, kitchen_id, equipment_type_code FROM household_cookware WHERE deleted_at IS NULL AND is_active = 1 AND condition = 'WORKING'
        UNION ALL SELECT household_id, kitchen_id, equipment_type_code FROM household_utensil WHERE deleted_at IS NULL AND is_active = 1 AND condition = 'WORKING') e
  JOIN equipment_type_cooking_method m ON m.equipment_type_code = e.equipment_type_code
 GROUP BY e.household_id, e.kitchen_id, m.cooking_method_code;
