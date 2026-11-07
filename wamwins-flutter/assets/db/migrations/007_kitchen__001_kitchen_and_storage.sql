-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: KITCHEN
CREATE TABLE kitchen (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    property_id TEXT,
    name TEXT NOT NULL,
    kitchen_type TEXT NOT NULL DEFAULT 'MAIN' CHECK (kitchen_type IN ('MAIN','SECONDARY','OUTDOOR','BASEMENT','PANTRY_ROOM','OFFICE','OTHER')),
    sort_order INTEGER NOT NULL DEFAULT 0,
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
    FOREIGN KEY (property_id, household_id) REFERENCES property(id, household_id),
    FOREIGN KEY (provenance_id, household_id) REFERENCES record_provenance(id, household_id)
) STRICT;
CREATE INDEX ix_kitchen_household ON kitchen(household_id) WHERE deleted_at IS NULL;

CREATE TABLE storage_type (
    code TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
    temperature_zone TEXT NOT NULL CHECK (temperature_zone IN ('AMBIENT','CHILLED','FROZEN','MIXED')),
    is_appliance_backed INTEGER NOT NULL DEFAULT 0 CHECK (is_appliance_backed IN (0,1)),
    sort_order INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))
) STRICT;

CREATE TABLE storage_section_template (
    id TEXT PRIMARY KEY,
    storage_type_code TEXT NOT NULL REFERENCES storage_type(code) ON DELETE CASCADE,
    section_kind TEXT NOT NULL CHECK (section_kind IN ('SHELF','DRAWER','DOOR_SHELF','CRISPER','BIN','BASKET','COMPARTMENT','RACK','ZONE','CUSTOM')),
    default_name TEXT NOT NULL,
    ordinal INTEGER NOT NULL DEFAULT 0,
    is_default_selected INTEGER NOT NULL DEFAULT 1 CHECK (is_default_selected IN (0,1)),
    UNIQUE (storage_type_code, default_name)
) STRICT;

CREATE TABLE storage_instance (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    storage_type_code TEXT NOT NULL REFERENCES storage_type(code),
    name TEXT NOT NULL,
    custom_type_label TEXT,
    temperature_zone TEXT CHECK (temperature_zone IN ('AMBIENT','CHILLED','FROZEN','MIXED')),
    household_appliance_id TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
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
    UNIQUE (id, kitchen_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (provenance_id, household_id) REFERENCES record_provenance(id, household_id),
    CHECK (storage_type_code <> 'CUSTOM' OR custom_type_label IS NOT NULL)
) STRICT;
CREATE INDEX ix_storage_kitchen ON storage_instance(kitchen_id) WHERE deleted_at IS NULL;

CREATE TABLE storage_section (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    storage_instance_id TEXT NOT NULL,
    parent_section_id TEXT,
    section_kind TEXT NOT NULL CHECK (section_kind IN ('SHELF','DRAWER','DOOR_SHELF','CRISPER','BIN','BASKET','COMPARTMENT','RACK','ZONE','CUSTOM')),
    name TEXT NOT NULL,
    ordinal INTEGER NOT NULL DEFAULT 0,
    depth INTEGER NOT NULL DEFAULT 0 CHECK (depth >= 0 AND depth < 32),
    path TEXT NOT NULL DEFAULT '',
    template_id TEXT REFERENCES storage_section_template(id) ON DELETE SET NULL,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    UNIQUE (id, storage_instance_id),
    FOREIGN KEY (storage_instance_id, household_id) REFERENCES storage_instance(id, household_id) ON DELETE CASCADE,
    FOREIGN KEY (parent_section_id, storage_instance_id) REFERENCES storage_section(id, storage_instance_id) ON DELETE CASCADE,
    CHECK (parent_section_id IS NULL OR parent_section_id <> id)
) STRICT;
CREATE INDEX ix_section_instance ON storage_section(storage_instance_id, parent_section_id, ordinal) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_section_path_root AFTER INSERT ON storage_section WHEN NEW.parent_section_id IS NULL
BEGIN UPDATE storage_section SET depth = 0, path = NEW.id WHERE id = NEW.id; END;
CREATE TRIGGER trg_section_path_child AFTER INSERT ON storage_section WHEN NEW.parent_section_id IS NOT NULL
BEGIN UPDATE storage_section SET depth = (SELECT depth + 1 FROM storage_section p WHERE p.id = NEW.parent_section_id),
                                   path  = (SELECT path || '/' || NEW.id FROM storage_section p WHERE p.id = NEW.parent_section_id)
      WHERE id = NEW.id; END;

CREATE TABLE storage_position (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    storage_section_id TEXT NOT NULL,
    label TEXT, row_index INTEGER, column_index INTEGER,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (storage_section_id, household_id) REFERENCES storage_section(id, household_id) ON DELETE CASCADE
) STRICT;
