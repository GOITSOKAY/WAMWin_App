-- WAMWins LOCAL (on-device) database | SQLite >= 3.37 (STRICT tables)
-- Mirrors the PostgreSQL model table-for-table (same table names without the PG schema).
-- Local-first: Basic works fully offline. Server-only concerns (RLS, partitions,
-- security-definer functions) live in database/postgres. Repositories maintain
-- updated_at/row_version; quantity integrity is enforced by triggers here too.
-- Module: INVENTORY
CREATE TABLE transaction_type (
    code TEXT PRIMARY KEY, name TEXT NOT NULL,
    quantity_effect TEXT NOT NULL CHECK (quantity_effect IN ('INCREASE','DECREASE','SIGNED')),
    requires_reason INTEGER NOT NULL DEFAULT 0 CHECK (requires_reason IN (0,1)), is_system INTEGER NOT NULL DEFAULT 1 CHECK (is_system IN (0,1))
) STRICT;

CREATE TABLE inventory_item (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    item_master_id TEXT NOT NULL REFERENCES item_master(id),
    kitchen_id TEXT NOT NULL,
    storage_instance_id TEXT NOT NULL,
    storage_section_id TEXT,
    container_id TEXT,
    quantity REAL NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    unit_code TEXT NOT NULL REFERENCES unit_of_measure(code),
    low_stock_threshold REAL CHECK (low_stock_threshold >= 0),
    purchased_on TEXT, opened_on TEXT, best_before_on TEXT, expires_on TEXT, use_soon_on TEXT,
    lifecycle_status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (lifecycle_status IN ('ACTIVE','OPENED','LOW','DEPLETED','EXPIRED','DISCARDED','ARCHIVED')),
    label TEXT, notes TEXT,
    last_transaction_id TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    last_source_code TEXT REFERENCES data_source_type(code),
    provenance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    deleted_at TEXT,
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER,
    last_modified_device_id TEXT,
    UNIQUE (id, household_id),
    FOREIGN KEY (kitchen_id, household_id) REFERENCES kitchen(id, household_id),
    FOREIGN KEY (storage_instance_id, kitchen_id) REFERENCES storage_instance(id, kitchen_id),
    FOREIGN KEY (storage_section_id, storage_instance_id) REFERENCES storage_section(id, storage_instance_id),
    FOREIGN KEY (container_id, household_id) REFERENCES household_container(id, household_id),
    FOREIGN KEY (provenance_id, household_id) REFERENCES record_provenance(id, household_id)
) STRICT;
CREATE INDEX ix_inv_storage ON inventory_item(storage_instance_id, storage_section_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_inv_master ON inventory_item(household_id, item_master_id) WHERE deleted_at IS NULL AND quantity > 0;
CREATE INDEX ix_inv_use_soon ON inventory_item(household_id, use_soon_on) WHERE deleted_at IS NULL AND lifecycle_status IN ('ACTIVE','OPENED','LOW');

CREATE TRIGGER trg_item_visible BEFORE INSERT ON inventory_item
WHEN NOT EXISTS (SELECT 1 FROM item_master i WHERE i.id = NEW.item_master_id AND (i.household_id IS NULL OR i.household_id = NEW.household_id))
BEGIN SELECT RAISE(ABORT, 'item_master is not visible to this household'); END;

CREATE TRIGGER trg_item_insert_zero BEFORE INSERT ON inventory_item WHEN NEW.quantity <> 0
BEGIN SELECT RAISE(ABORT, 'inventory_item must be created with quantity 0; record an OPENING_BALANCE/MANUAL_ADD transaction'); END;

CREATE TRIGGER trg_item_quantity_guard BEFORE UPDATE OF quantity ON inventory_item
WHEN NEW.quantity <> OLD.quantity AND NOT EXISTS (
    SELECT 1 FROM inventory_transaction t WHERE t.id = NEW.last_transaction_id AND t.inventory_item_id = NEW.id AND t.quantity_after = NEW.quantity)
BEGIN SELECT RAISE(ABORT, 'inventory quantity can only change through inventory_transaction'); END;

CREATE TABLE inventory_transaction (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    inventory_item_id TEXT NOT NULL,
    transaction_type_code TEXT NOT NULL REFERENCES transaction_type(code),
    quantity_delta REAL NOT NULL CHECK (quantity_delta <> 0),
    unit_code TEXT NOT NULL REFERENCES unit_of_measure(code),
    quantity_before REAL NOT NULL,
    quantity_after REAL NOT NULL CHECK (quantity_after >= 0),
    occurred_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    recorded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    actor_user_id TEXT, source_device_id TEXT,
    transfer_group_id TEXT, related_inventory_item_id TEXT,
    meal_record_id TEXT, shopping_list_item_id TEXT,
    reason TEXT,
    created_source_code TEXT NOT NULL DEFAULT 'MANUAL' REFERENCES data_source_type(code),
    provenance_id TEXT,
    idempotency_key TEXT,
    server_sync_version INTEGER,
    FOREIGN KEY (inventory_item_id, household_id) REFERENCES inventory_item(id, household_id) ON DELETE CASCADE,
    UNIQUE (household_id, idempotency_key)
) STRICT;
CREATE INDEX ix_txn_item ON inventory_transaction(inventory_item_id, occurred_at);

CREATE TRIGGER trg_txn_validate BEFORE INSERT ON inventory_transaction
BEGIN
    SELECT RAISE(ABORT, 'transaction unit must match inventory item unit')
     WHERE NEW.unit_code <> (SELECT unit_code FROM inventory_item WHERE id = NEW.inventory_item_id);
    SELECT RAISE(ABORT, 'quantity_delta sign does not match transaction type')
     WHERE EXISTS (SELECT 1 FROM transaction_type tt WHERE tt.code = NEW.transaction_type_code
                    AND ((tt.quantity_effect = 'INCREASE' AND NEW.quantity_delta <= 0) OR (tt.quantity_effect = 'DECREASE' AND NEW.quantity_delta >= 0)));
    SELECT RAISE(ABORT, 'quantity_before must equal current item quantity and quantity_after = before + delta')
     WHERE abs(NEW.quantity_before - (SELECT quantity FROM inventory_item WHERE id = NEW.inventory_item_id)) > 0.00005
        OR abs(NEW.quantity_after - (NEW.quantity_before + NEW.quantity_delta)) > 0.00005;
END;

CREATE TRIGGER trg_txn_apply AFTER INSERT ON inventory_transaction
BEGIN
    UPDATE inventory_item
       SET quantity = NEW.quantity_after,
           last_transaction_id = NEW.id,
           last_source_code = NEW.created_source_code,
           updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
           row_version = row_version + 1,
           lifecycle_status = CASE
               WHEN NEW.quantity_after = 0 AND NEW.transaction_type_code = 'EXPIRED' THEN 'EXPIRED'
               WHEN NEW.quantity_after = 0 AND NEW.transaction_type_code = 'WASTE' THEN 'DISCARDED'
               WHEN NEW.quantity_after = 0 THEN 'DEPLETED'
               WHEN low_stock_threshold IS NOT NULL AND NEW.quantity_after <= low_stock_threshold THEN 'LOW'
               WHEN opened_on IS NOT NULL THEN 'OPENED'
               ELSE 'ACTIVE' END
     WHERE id = NEW.inventory_item_id;
END;

CREATE TRIGGER trg_txn_no_update BEFORE UPDATE ON inventory_transaction
BEGIN SELECT RAISE(ABORT, 'inventory_transaction is append-only; write a CORRECTION'); END;
CREATE TRIGGER trg_txn_no_delete BEFORE DELETE ON inventory_transaction
WHEN EXISTS (SELECT 1 FROM household h WHERE h.id = OLD.household_id AND h.status <> 'PENDING_DELETION')
BEGIN SELECT RAISE(ABORT, 'inventory_transaction is append-only; rows are removed only by household erasure'); END;

CREATE VIEW v_use_soon AS
SELECT i.household_id, i.id AS inventory_item_id, i.item_master_id, i.kitchen_id, i.storage_instance_id,
       i.quantity, i.unit_code, COALESCE(i.use_soon_on, i.expires_on, i.best_before_on) AS use_by
  FROM inventory_item i
 WHERE i.deleted_at IS NULL AND i.quantity > 0 AND i.lifecycle_status IN ('ACTIVE','OPENED','LOW')
   AND COALESCE(i.use_soon_on, i.expires_on, i.best_before_on) IS NOT NULL;
