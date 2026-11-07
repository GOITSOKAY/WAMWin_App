-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: MODULE_REGISTRY
CREATE TABLE module_definition (
    id TEXT PRIMARY KEY,
    module_code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    module_kind TEXT NOT NULL CHECK (module_kind IN ('CORE','DOMAIN','OPTIONAL_CAPABILITY')),
    version TEXT NOT NULL DEFAULT '1.0.0',
    schema_version INTEGER NOT NULL DEFAULT 1,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
    lazy_load_enabled INTEGER NOT NULL DEFAULT 1 CHECK (lazy_load_enabled IN (0,1)),
    supports_instances INTEGER NOT NULL DEFAULT 0 CHECK (supports_instances IN (0,1)),
    current_status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (current_status IN ('ACTIVE','INACTIVE','LOADING','DEGRADED','MAINTENANCE','FROZEN','ERROR','DISABLED')),
    health_status TEXT NOT NULL DEFAULT 'HEALTHY' CHECK (health_status IN ('HEALTHY','WARNING','UNHEALTHY','UNKNOWN')),
    minimum_tier_number INTEGER CHECK (minimum_tier_number BETWEEN 1 AND 7),
    owner_schema TEXT,
    local_migration_dir TEXT,           -- optional modules install their local tables lazily
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;

CREATE TABLE module_dependency (
    module_id TEXT NOT NULL REFERENCES module_definition(id) ON DELETE CASCADE,
    depends_on_module_id TEXT NOT NULL REFERENCES module_definition(id),
    dependency_type TEXT NOT NULL CHECK (dependency_type IN ('HARD','SOFT')),
    PRIMARY KEY (module_id, depends_on_module_id),
    CHECK (module_id <> depends_on_module_id)
) STRICT;

CREATE TABLE module_capability_requirement (
    module_id TEXT NOT NULL REFERENCES module_definition(id) ON DELETE CASCADE,
    capability_id TEXT NOT NULL REFERENCES capability(id),
    PRIMARY KEY (module_id, capability_id)
) STRICT;

CREATE TABLE tier_module_entitlement (
    id TEXT PRIMARY KEY,
    tier_id TEXT NOT NULL REFERENCES product_tier(id),
    module_id TEXT NOT NULL REFERENCES module_definition(id),
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
    reason TEXT,
    effective_from TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    effective_to TEXT
) STRICT;

CREATE TABLE module_status_transition (from_status TEXT NOT NULL, to_status TEXT NOT NULL, PRIMARY KEY (from_status, to_status)) STRICT;

CREATE TABLE household_module_instance (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    module_id TEXT NOT NULL REFERENCES module_definition(id),
    resource_type TEXT,
    resource_id TEXT,
    display_name TEXT,
    current_status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (current_status IN ('ACTIVE','INACTIVE','LOADING','DEGRADED','MAINTENANCE','FROZEN','ERROR','DISABLED')),
    activated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    frozen_at TEXT,
    frozen_reason TEXT,
    error_count INTEGER NOT NULL DEFAULT 0,
    last_error_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    CHECK ((resource_type IS NULL) = (resource_id IS NULL))
) STRICT;
CREATE UNIQUE INDEX ux_hmi_module ON household_module_instance(household_id, module_id) WHERE resource_id IS NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX ux_hmi_resource ON household_module_instance(household_id, module_id, resource_id) WHERE resource_id IS NOT NULL AND deleted_at IS NULL;

CREATE TRIGGER trg_module_status_transition BEFORE UPDATE OF current_status ON module_definition
WHEN NEW.current_status <> OLD.current_status AND NOT EXISTS (SELECT 1 FROM module_status_transition t WHERE t.from_status = OLD.current_status AND t.to_status = NEW.current_status)
BEGIN SELECT RAISE(ABORT, 'Illegal module status transition'); END;
CREATE TRIGGER trg_instance_status_transition BEFORE UPDATE OF current_status ON household_module_instance
WHEN NEW.current_status <> OLD.current_status AND NOT EXISTS (SELECT 1 FROM module_status_transition t WHERE t.from_status = OLD.current_status AND t.to_status = NEW.current_status)
BEGIN SELECT RAISE(ABORT, 'Illegal module status transition'); END;

CREATE TABLE module_health_event (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    module_id TEXT NOT NULL REFERENCES module_definition(id),
    household_id TEXT REFERENCES household(id) ON DELETE CASCADE,
    module_instance_id TEXT REFERENCES household_module_instance(id) ON DELETE CASCADE,
    scope TEXT NOT NULL CHECK (scope IN ('GLOBAL','HOUSEHOLD','INSTANCE')),
    event_type TEXT NOT NULL CHECK (event_type IN ('HEALTH_CHECK_OK','HEALTH_CHECK_FAILED','ERROR','DEGRADED','FROZEN','MAINTENANCE_STARTED','PATCH_APPLIED','TEST_PASSED','TEST_FAILED','REACTIVATED','DISABLED')),
    status_from TEXT, status_to TEXT, error_code TEXT, error_message TEXT, app_version TEXT, device_platform TEXT,
    occurred_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
CREATE INDEX ix_health_event_module ON module_health_event(module_id, occurred_at);

CREATE TABLE domain_event_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    household_id TEXT,
    module_code TEXT NOT NULL,
    event_type TEXT NOT NULL,
    aggregate_type TEXT NOT NULL,
    aggregate_id TEXT,
    payload TEXT NOT NULL DEFAULT '{}',
    occurred_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    processed_at TEXT,
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
) STRICT;
CREATE INDEX ix_outbox_pending ON domain_event_outbox(processed_at) WHERE processed_at IS NULL;

CREATE TABLE audit_event (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    occurred_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    household_id TEXT, actor_user_id TEXT,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('USER','SYSTEM','SERVICE','SUPPORT')),
    action TEXT NOT NULL, entity_table TEXT, entity_id TEXT, module_code TEXT, source_device_id TEXT,
    changed_fields TEXT
) STRICT;
