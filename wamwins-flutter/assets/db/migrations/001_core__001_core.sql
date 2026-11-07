-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: CORE
CREATE TABLE data_source_type (
    code TEXT PRIMARY KEY CHECK (code GLOB '[A-Z]*'),
    name TEXT NOT NULL,
    description TEXT,
    is_automated INTEGER NOT NULL DEFAULT 0 CHECK (is_automated IN (0,1)),
    requires_review INTEGER NOT NULL DEFAULT 0 CHECK (requires_review IN (0,1)),
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    sort_order INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE TABLE module_schema_version (
    module_code TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    migration_ref TEXT NOT NULL,
    description TEXT,
    applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY (module_code, schema_version)
) STRICT;

CREATE TABLE user_account (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL COLLATE NOCASE,
    display_name TEXT NOT NULL,
    locale TEXT NOT NULL DEFAULT 'en',
    timezone TEXT NOT NULL DEFAULT 'UTC',
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','SUSPENDED','PENDING_DELETION','DELETED')),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT
) STRICT;
CREATE UNIQUE INDEX ux_user_account_email ON user_account(email) WHERE deleted_at IS NULL;

CREATE TABLE user_device (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('ANDROID','IOS','WEB_PWA','OTHER')),
    device_label TEXT,
    app_version TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    last_seen_at TEXT,
    revoked_at TEXT
) STRICT;

CREATE TABLE consent_record (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    consent_type TEXT NOT NULL CHECK (consent_type IN ('TERMS','PRIVACY_POLICY','HEALTH_DATA_PROCESSING','MEDIA_PROCESSING','THIRD_PARTY_SHARING','MARKETING')),
    document_version TEXT NOT NULL,
    granted INTEGER NOT NULL CHECK (granted IN (0,1)),
    recorded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    source_device_id TEXT
) STRICT;

CREATE TABLE household (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_user_id TEXT NOT NULL REFERENCES user_account(id),
    timezone TEXT NOT NULL DEFAULT 'UTC',
    locale TEXT NOT NULL DEFAULT 'en',
    country_code TEXT,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ARCHIVED','PENDING_DELETION')),
    onboarding_status TEXT NOT NULL DEFAULT 'NOT_STARTED' CHECK (onboarding_status IN ('NOT_STARTED','IN_PROGRESS','COMPLETED')),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT
) STRICT;

CREATE TABLE role (code TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, rank INTEGER NOT NULL, is_system INTEGER NOT NULL DEFAULT 1 CHECK (is_system IN (0,1))) STRICT;
CREATE TABLE permission (code TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, description TEXT) STRICT;
CREATE TABLE role_permission (
    role_code TEXT NOT NULL REFERENCES role(code) ON DELETE CASCADE,
    permission_code TEXT NOT NULL REFERENCES permission(code) ON DELETE CASCADE,
    PRIMARY KEY (role_code, permission_code)
) STRICT;

CREATE TABLE household_membership (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    role_code TEXT NOT NULL REFERENCES role(code),
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('INVITED','ACTIVE','SUSPENDED','REMOVED')),
    joined_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT
) STRICT;
CREATE UNIQUE INDEX ux_membership ON household_membership(household_id, user_id) WHERE deleted_at IS NULL;

CREATE TABLE property (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    property_type TEXT NOT NULL DEFAULT 'PRIMARY_RESIDENCE' CHECK (property_type IN ('PRIMARY_RESIDENCE','SECONDARY_RESIDENCE','RENTAL','OFFICE','OTHER')),
    city TEXT, region TEXT, country_code TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id)
) STRICT;

CREATE TABLE record_provenance (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    source_type_code TEXT NOT NULL REFERENCES data_source_type(code),
    source_device_id TEXT,
    actor_user_id TEXT,
    recognition_confidence REAL CHECK (recognition_confidence BETWEEN 0 AND 1),
    external_reference TEXT,
    media_asset_id TEXT, capture_session_id TEXT, recognition_result_id TEXT, barcode_reference_id TEXT,
    receipt_import_id TEXT, ocr_result_id TEXT, provider_connection_id TEXT, automation_rule_id TEXT,
    external_integration_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE (id, household_id)
) STRICT;
