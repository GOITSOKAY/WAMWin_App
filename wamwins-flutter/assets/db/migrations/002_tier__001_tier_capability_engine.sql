-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: TIER_ENGINE
CREATE TABLE product (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, description TEXT, active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))) STRICT;

CREATE TABLE product_tier (
    id TEXT PRIMARY KEY,
    product_id TEXT NOT NULL REFERENCES product(id),
    tier_number INTEGER NOT NULL CHECK (tier_number BETWEEN 1 AND 7),
    tier_code TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    configuration_status TEXT NOT NULL DEFAULT 'UNDEFINED' CHECK (configuration_status IN ('CONFIGURED','UNDEFINED')),
    active INTEGER NOT NULL DEFAULT 0 CHECK (active IN (0,1)),
    effective_from TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    effective_to TEXT,
    UNIQUE (id, product_id),
    CHECK (active = 0 OR configuration_status = 'CONFIGURED')
) STRICT;
CREATE UNIQUE INDEX ux_product_tier_current ON product_tier(product_id, tier_number) WHERE effective_to IS NULL;

CREATE TABLE capability (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('HOUSEHOLD','FOOD','KITCHEN','CAPTURE','RECOGNITION','INTELLIGENCE','AUTOMATION','INTEGRATION','SERVICES','ENTERPRISE','PLATFORM_SAFETY','TEST')),
    is_platform_guaranteed INTEGER NOT NULL DEFAULT 0 CHECK (is_platform_guaranteed IN (0,1)),
    is_test INTEGER NOT NULL DEFAULT 0 CHECK (is_test IN (0,1)),
    definition_version INTEGER NOT NULL DEFAULT 1,
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))
) STRICT;

CREATE TABLE capability_parameter_definition (
    id TEXT PRIMARY KEY,
    capability_id TEXT NOT NULL REFERENCES capability(id) ON DELETE CASCADE,
    parameter_code TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('LIMIT','SETTING')),
    value_type TEXT NOT NULL CHECK (value_type IN ('INTEGER','DECIMAL','BOOLEAN','TEXT')),
    unit TEXT, description TEXT,
    UNIQUE (capability_id, parameter_code)
) STRICT;

CREATE TABLE tier_capability (
    id TEXT PRIMARY KEY,
    tier_id TEXT NOT NULL REFERENCES product_tier(id),
    capability_id TEXT NOT NULL REFERENCES capability(id),
    status TEXT NOT NULL CHECK (status IN ('ENABLED','DISABLED','UNDEFINED')),
    effective_from TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    effective_to TEXT
) STRICT;
CREATE UNIQUE INDEX ux_tier_capability_current ON tier_capability(tier_id, capability_id) WHERE effective_to IS NULL;
CREATE TRIGGER trg_guard_platform_capability BEFORE INSERT ON tier_capability
WHEN NEW.status <> 'ENABLED' AND EXISTS (SELECT 1 FROM capability c WHERE c.id = NEW.capability_id AND c.is_platform_guaranteed = 1)
BEGIN SELECT RAISE(ABORT, 'Platform-guaranteed capability cannot be withheld by a tier'); END;

CREATE TABLE tier_capability_parameter (
    id TEXT PRIMARY KEY,
    tier_capability_id TEXT NOT NULL REFERENCES tier_capability(id) ON DELETE CASCADE,
    parameter_definition_id TEXT NOT NULL REFERENCES capability_parameter_definition(id),
    integer_value INTEGER, decimal_value REAL, boolean_value INTEGER, text_value TEXT,
    UNIQUE (tier_capability_id, parameter_definition_id),
    CHECK ((integer_value IS NOT NULL) + (decimal_value IS NOT NULL) + (boolean_value IS NOT NULL) + (text_value IS NOT NULL) = 1)
) STRICT;

CREATE TABLE subscription (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES product(id),
    product_tier_id TEXT NOT NULL,
    billing_user_id TEXT,
    status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('TRIAL','ACTIVE','PAST_DUE','CANCELLED','EXPIRED')),
    started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    current_period_end TEXT, cancelled_at TEXT, ended_at TEXT,
    source_code TEXT NOT NULL DEFAULT 'SYSTEM_DEFAULT' REFERENCES data_source_type(code),
    external_reference TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (product_tier_id, product_id) REFERENCES product_tier(id, product_id)
) STRICT;
CREATE UNIQUE INDEX ux_subscription_live ON subscription(household_id, product_id) WHERE status IN ('TRIAL','ACTIVE','PAST_DUE');

CREATE TABLE subscription_tier_history (
    id TEXT PRIMARY KEY,
    subscription_id TEXT NOT NULL REFERENCES subscription(id) ON DELETE CASCADE,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    from_tier_id TEXT REFERENCES product_tier(id),
    to_tier_id TEXT NOT NULL REFERENCES product_tier(id),
    reason TEXT NOT NULL CHECK (reason IN ('INITIAL','UPGRADE','DOWNGRADE','RENEWAL','ADMIN','TEST')),
    changed_by_user_id TEXT,
    changed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;

CREATE TABLE entitlement_override (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    capability_id TEXT NOT NULL REFERENCES capability(id),
    status TEXT NOT NULL CHECK (status IN ('ENABLED','DISABLED')),
    reason TEXT NOT NULL,
    granted_by_user_id TEXT,
    effective_from TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    effective_to TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;

CREATE TABLE subscription_entitlement (
    id TEXT PRIMARY KEY,
    subscription_id TEXT NOT NULL REFERENCES subscription(id) ON DELETE CASCADE,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    capability_id TEXT NOT NULL REFERENCES capability(id),
    status TEXT NOT NULL CHECK (status IN ('ENABLED','DISABLED','UNDEFINED')),
    is_entitled INTEGER GENERATED ALWAYS AS (status = 'ENABLED') STORED,
    resolved_from TEXT NOT NULL CHECK (resolved_from IN ('TIER','OVERRIDE','PLATFORM_GUARANTEE')),
    computed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    server_sync_version INTEGER,
    UNIQUE (subscription_id, capability_id)
) STRICT;
CREATE INDEX ix_entitlement_household ON subscription_entitlement(household_id, capability_id);

CREATE TABLE subscription_entitlement_parameter (
    entitlement_id TEXT NOT NULL REFERENCES subscription_entitlement(id) ON DELETE CASCADE,
    parameter_definition_id TEXT NOT NULL REFERENCES capability_parameter_definition(id),
    integer_value INTEGER, decimal_value REAL, boolean_value INTEGER, text_value TEXT,
    PRIMARY KEY (entitlement_id, parameter_definition_id)
) STRICT;

CREATE TABLE entitlement_change_log (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    subscription_id TEXT NOT NULL REFERENCES subscription(id) ON DELETE CASCADE,
    capability_id TEXT NOT NULL REFERENCES capability(id),
    previous_status TEXT,
    new_status TEXT NOT NULL,
    reason TEXT NOT NULL,
    changed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
