-- WAMWins LOCAL database | Entry Module v2 (seven-module onboarding). ADDITIVE ONLY:
-- new reference tables, new nullable columns, new tables, and a widened cooking-capability view.
-- No table is rebuilt, no CHECK is altered, no existing row is changed. Mirrors PostgreSQL V027.

-- ---- reference: kitchen kinds (Barn / Mobile added; legacy kitchen_type kept for the old CHECK)
CREATE TABLE kitchen_kind (
    code TEXT PRIMARY KEY, name TEXT NOT NULL,
    legacy_kitchen_type TEXT NOT NULL CHECK (legacy_kitchen_type IN ('MAIN','SECONDARY','OUTDOOR','BASEMENT','PANTRY_ROOM','OFFICE','OTHER')),
    sort_order INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))
) STRICT;
ALTER TABLE kitchen ADD COLUMN kitchen_kind_code TEXT REFERENCES kitchen_kind(code);

-- ---- reference: roles in the household (extensible, not gender-fixed)
CREATE TABLE household_role (code TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1) STRICT;
ALTER TABLE family_member ADD COLUMN household_role_code TEXT REFERENCES household_role(code);
ALTER TABLE family_member ADD COLUMN cooking_responsibility TEXT CHECK (cooking_responsibility IN ('PRIMARY','SHARED','OTHER'));
ALTER TABLE household ADD COLUMN nickname TEXT;
ALTER TABLE household ADD COLUMN member_count INTEGER CHECK (member_count > 0);
ALTER TABLE household ADD COLUMN eater_count INTEGER CHECK (eater_count >= 0);

-- ---- health: foods to avoid / prioritize, per meal context (structured, never one text blob)
CREATE TABLE member_food_rule (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    member_id TEXT NOT NULL REFERENCES family_member(id) ON DELETE CASCADE,
    rule_kind TEXT NOT NULL CHECK (rule_kind IN ('AVOID','PRIORITIZE','NOTE')),
    meal_context TEXT NOT NULL DEFAULT 'ANY' CHECK (meal_context IN ('ANY','BREAKFAST','LUNCH','DINNER','SNACK','BEVERAGE')),
    item_master_id TEXT REFERENCES item_master(id),
    food_category_code TEXT REFERENCES food_category(code),
    label TEXT NOT NULL,
    note TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT, row_version INTEGER NOT NULL DEFAULT 1, server_sync_version INTEGER
) STRICT;
CREATE INDEX ix_food_rule_member ON member_food_rule(member_id, meal_context) WHERE deleted_at IS NULL;

-- ---- storage: follow-up questions that create sections (shelves, crispers, door shelves, bins, ...)
CREATE TABLE storage_section_question (
    storage_type_code TEXT NOT NULL REFERENCES storage_type(code),
    code TEXT NOT NULL, label TEXT NOT NULL,
    section_kind TEXT NOT NULL CHECK (section_kind IN ('SHELF','DRAWER','DOOR_SHELF','CRISPER','BIN','BASKET','COMPARTMENT','RACK','ZONE','CUSTOM')),
    name_pattern TEXT NOT NULL,                       -- e.g. 'Shelf {n}' or 'Freezer section'
    input_kind TEXT NOT NULL CHECK (input_kind IN ('COUNT','TOGGLE')),
    default_value INTEGER NOT NULL DEFAULT 0, max_value INTEGER NOT NULL DEFAULT 10, sort_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (storage_type_code, code)
) STRICT;

-- ---- appliances: details + cross-reference to the storage unit it provides (refrigerator / freezer)
ALTER TABLE household_appliance ADD COLUMN serial_number TEXT;
ALTER TABLE household_appliance ADD COLUMN purchased_on TEXT;
ALTER TABLE household_appliance ADD COLUMN warranty_end_on TEXT;
ALTER TABLE household_appliance ADD COLUMN location_note TEXT;
ALTER TABLE household_appliance ADD COLUMN storage_instance_id TEXT REFERENCES storage_instance(id);
ALTER TABLE equipment_type ADD COLUMN power_source TEXT CHECK (power_source IN ('ELECTRIC','GAS','MANUAL','OTHER'));
ALTER TABLE equipment_type ADD COLUMN size_rank INTEGER;

-- ---- kitchenware: dinnerware, flatware, cookware & tools, glassware, others (with quantities)
CREATE TABLE kitchenware_type (
    code TEXT PRIMARY KEY,
    category TEXT NOT NULL CHECK (category IN ('DINNERWARE','FLATWARE','COOKWARE','GLASSWARE','OTHER')),
    name TEXT NOT NULL,
    equipment_type_code TEXT,                          -- cookware/tools that enable cooking methods (matching)
    sort_order INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1))
) STRICT;
CREATE TABLE household_kitchenware (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT NOT NULL,
    kitchenware_type_code TEXT REFERENCES kitchenware_type(code),   -- NULL for the household's own items
    category TEXT NOT NULL CHECK (category IN ('DINNERWARE','FLATWARE','COOKWARE','GLASSWARE','OTHER')),
    name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT, row_version INTEGER NOT NULL DEFAULT 1, server_sync_version INTEGER,
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id)
) STRICT;
CREATE INDEX ix_kitchenware_kitchen ON household_kitchenware(kitchen_id) WHERE deleted_at IS NULL;

-- cooking capability now also counts cookware/tools recorded as kitchenware
DROP VIEW v_household_cooking_capability;
CREATE VIEW v_household_cooking_capability AS
SELECT e.household_id, e.kitchen_id, m.cooking_method_code, COUNT(*) AS equipment_count
  FROM (SELECT household_id, kitchen_id, equipment_type_code FROM household_appliance WHERE deleted_at IS NULL AND is_active = 1 AND condition = 'WORKING'
        UNION ALL SELECT household_id, kitchen_id, equipment_type_code FROM household_cookware WHERE deleted_at IS NULL AND is_active = 1 AND condition = 'WORKING'
        UNION ALL SELECT household_id, kitchen_id, equipment_type_code FROM household_utensil WHERE deleted_at IS NULL AND is_active = 1 AND condition = 'WORKING'
        UNION ALL SELECT k.household_id, k.kitchen_id, t.equipment_type_code FROM household_kitchenware k JOIN kitchenware_type t ON t.code = k.kitchenware_type_code
                   WHERE k.deleted_at IS NULL AND k.is_active = 1 AND t.equipment_type_code IS NOT NULL) e
  JOIN equipment_type_cooking_method m ON m.equipment_type_code = e.equipment_type_code
 GROUP BY e.household_id, e.kitchen_id, m.cooking_method_code;

-- ---- food inventory details
CREATE TABLE packaging_type (code TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0) STRICT;
ALTER TABLE inventory_item ADD COLUMN brand TEXT;
ALTER TABLE inventory_item ADD COLUMN packaging_code TEXT REFERENCES packaging_type(code);
ALTER TABLE inventory_item ADD COLUMN package_size REAL CHECK (package_size > 0);
ALTER TABLE inventory_item ADD COLUMN package_unit_code TEXT REFERENCES unit_of_measure(code);
ALTER TABLE inventory_item ADD COLUMN use_by_on TEXT;
ALTER TABLE inventory_item ADD COLUMN item_condition TEXT CHECK (item_condition IN ('NEW','GOOD','FAIR','POOR'));

-- ---- manual reference photos (Basic): metadata here, image bytes in media_blob (kept out of large rows)
CREATE TABLE location_media (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    kitchen_id TEXT, storage_instance_id TEXT, storage_section_id TEXT, container_id TEXT, inventory_item_id TEXT,
    location_draft_key TEXT,                           -- set while onboarding; ids are filled when entries are saved
    media_type TEXT NOT NULL DEFAULT 'IMAGE' CHECK (media_type IN ('IMAGE')),
    blob_ref TEXT NOT NULL, thumbnail_ref TEXT, mime_type TEXT NOT NULL, byte_size INTEGER,
    title TEXT, caption TEXT,
    uploaded_by_user_id TEXT REFERENCES user_account(id) ON DELETE SET NULL,
    source_type TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    archived_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    row_version INTEGER NOT NULL DEFAULT 1, server_sync_version INTEGER
) STRICT;
CREATE INDEX ix_media_location ON location_media(household_id, kitchen_id, storage_instance_id, storage_section_id) WHERE archived_at IS NULL;
CREATE INDEX ix_media_draft ON location_media(household_id, location_draft_key) WHERE location_draft_key IS NOT NULL;
CREATE TABLE media_blob (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    mime_type TEXT NOT NULL,
    bytes BLOB NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
