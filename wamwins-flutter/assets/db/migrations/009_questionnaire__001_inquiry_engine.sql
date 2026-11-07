-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: QUESTIONNAIRE
CREATE TABLE questionnaire (
    id TEXT PRIMARY KEY, code TEXT NOT NULL, version INTEGER NOT NULL, title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED','RETIRED')),
    published_at TEXT, UNIQUE (code, version)
) STRICT;
CREATE TABLE question (
    id TEXT PRIMARY KEY,
    questionnaire_id TEXT NOT NULL REFERENCES questionnaire(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    section TEXT NOT NULL CHECK (section IN ('USER','HOUSEHOLD','FAMILY','HEALTH','KITCHEN','STORAGE','EQUIPMENT','INVENTORY','PREFERENCES')),
    prompt TEXT NOT NULL, help_text TEXT,
    answer_type TEXT NOT NULL CHECK (answer_type IN ('SINGLE_CHOICE','MULTI_CHOICE','COUNT','NUMBER','TEXT','BOOLEAN','DATE','COUNT_PER_OPTION')),
    is_required INTEGER NOT NULL DEFAULT 0 CHECK (is_required IN (0,1)),
    ordinal INTEGER NOT NULL,
    repeat_per TEXT NOT NULL DEFAULT 'NONE' CHECK (repeat_per IN ('NONE','KITCHEN','STORAGE_INSTANCE','FAMILY_MEMBER')),
    required_capability_id TEXT REFERENCES capability(id),
    hidden_when_capability_id TEXT REFERENCES capability(id),
    UNIQUE (questionnaire_id, code)
) STRICT;
CREATE TABLE question_option (
    id TEXT PRIMARY KEY, question_id TEXT NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    code TEXT NOT NULL, label TEXT NOT NULL, ordinal INTEGER NOT NULL DEFAULT 0, UNIQUE (question_id, code)
) STRICT;
CREATE TABLE question_condition (
    id TEXT PRIMARY KEY, question_id TEXT NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    depends_on_question_id TEXT NOT NULL REFERENCES question(id),
    operator TEXT NOT NULL CHECK (operator IN ('EQUALS','NOT_EQUALS','INCLUDES','GREATER_THAN','ANSWERED')),
    option_code TEXT, number_value REAL, group_no INTEGER NOT NULL DEFAULT 1
) STRICT;
CREATE TABLE provisioning_rule (
    id TEXT PRIMARY KEY, question_id TEXT NOT NULL REFERENCES question(id) ON DELETE CASCADE,
    option_code TEXT,
    action_type TEXT NOT NULL CHECK (action_type IN ('CREATE_KITCHEN','CREATE_STORAGE_INSTANCE','CREATE_SECTIONS_FROM_TEMPLATE','CREATE_FAMILY_MEMBER','CREATE_APPLIANCE','CREATE_EQUIPMENT','ACTIVATE_MODULE','SET_HOUSEHOLD_ATTRIBUTE')),
    target_storage_type_code TEXT REFERENCES storage_type(code),
    target_equipment_type_code TEXT REFERENCES equipment_type(code),
    target_module_code TEXT,
    quantity_source TEXT NOT NULL DEFAULT 'ONE' CHECK (quantity_source IN ('ONE','ANSWER_NUMBER')),
    ordinal INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE TABLE questionnaire_session (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES user_account(id),
    questionnaire_id TEXT NOT NULL REFERENCES questionnaire(id),
    scope_kitchen_id TEXT,
    status TEXT NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS','COMPLETED','ABANDONED')),
    started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id)
) STRICT;
CREATE TABLE answer (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    question_id TEXT NOT NULL REFERENCES question(id),
    repeat_key TEXT NOT NULL DEFAULT '',
    option_code TEXT, text_value TEXT, number_value REAL, boolean_value INTEGER, date_value TEXT,
    answered_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), superseded_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    FOREIGN KEY (session_id, household_id) REFERENCES questionnaire_session(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE UNIQUE INDEX ux_answer_current ON answer(session_id, question_id, repeat_key, IFNULL(option_code, '')) WHERE superseded_at IS NULL AND deleted_at IS NULL;
CREATE TABLE provisioning_record (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL REFERENCES questionnaire_session(id) ON DELETE CASCADE,
    answer_id TEXT NOT NULL REFERENCES answer(id) ON DELETE CASCADE,
    rule_id TEXT NOT NULL REFERENCES provisioning_rule(id),
    ordinal_index INTEGER NOT NULL DEFAULT 0,
    created_entity_table TEXT NOT NULL,
    created_entity_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE (answer_id, rule_id, ordinal_index)
) STRICT;
