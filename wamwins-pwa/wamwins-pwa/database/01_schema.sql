-- =====================================================================
-- WAM Digital / WAMWins — Kitchen Management & Health Matching
-- Core database schema v1.0  (PostgreSQL 15+; Supabase-compatible)
-- Serves WAMWins Basic (Free tier) and is structured for higher tiers.
-- Principles: tenant isolation by household_id + RLS, capability-based
-- entitlements, append-only inventory ledger, soft delete + sync cursor,
-- health data isolated in its own schema, explainable matching.
-- =====================================================================
create extension if not exists pg_trgm;
create extension if not exists citext;

create schema core;     -- identity, households, plans, entitlements, consent, audit
create schema ref;      -- master data (system-wide, optionally household-custom)
create schema hh;       -- household operational data (kitchen, family, inventory, meals)
create schema health;   -- sensitive member food/health requirements
create schema capture;  -- Tier 2+ extension: image/video/barcode/receipt capture
create schema match;    -- meal matching runs and explainable results

create sequence core.rev_seq;  -- global change cursor used for offline sync

create function core.uid() returns uuid language sql stable as
$$ select nullif(current_setting('app.user_id', true), '')::uuid $$;   -- map to auth.uid() on Supabase

create function core.touch() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.rev := nextval('core.rev_seq');
  return new;
end $$;

-- ============================ CORE: PLANS & ENTITLEMENTS ==============
create table core.plans (
  id smallint primary key,
  code text not null unique,
  name text not null,
  tier_level smallint not null unique check (tier_level between 1 and 7),
  is_active boolean not null default true
);
create table core.capabilities (
  code text primary key,
  description text not null
);
create table core.plan_capabilities (
  plan_id smallint not null references core.plans(id),
  capability_code text not null references core.capabilities(code),
  primary key (plan_id, capability_code)
);
create table core.plan_limits (       -- absent row = unlimited
  plan_id smallint not null references core.plans(id),
  limit_code text not null,
  limit_value int not null check (limit_value >= 0),
  primary key (plan_id, limit_code)
);

-- ============================ CORE: IDENTITY & HOUSEHOLD ==============
create table core.users (
  id uuid primary key,                       -- = auth provider subject id
  email citext not null unique,
  first_name text, last_name text,
  locale text not null default 'en-US',
  timezone text,
  email_verified_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table core.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  country_code char(2) not null default 'US',
  region_code text,
  timezone text,
  locale text not null default 'en-US',
  measurement_system text not null default 'us' check (measurement_system in ('us','metric')),
  people_count smallint check (people_count between 1 and 50),
  owner_user_id uuid not null references core.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table core.household_subscriptions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  plan_id smallint not null references core.plans(id),
  status text not null default 'active' check (status in ('active','trialing','past_due','canceled','expired')),
  source text not null default 'free' check (source in ('free','app_store','google_play','web','admin')),
  external_ref text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create unique index uq_one_active_subscription on core.household_subscriptions(household_id)
  where status in ('active','trialing') and deleted_at is null;

create table core.household_memberships (   -- ACCOUNT access (a seat). Not the same as a family member profile.
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  user_id uuid not null references core.users(id),
  role text not null default 'member' check (role in ('owner','admin','kitchen_manager','member','limited')),
  status text not null default 'active' check (status in ('active','invited','removed')),
  unique (household_id, user_id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);

create function core.active_plan(hh uuid) returns smallint language sql stable security definer
set search_path = core, pg_temp as $$
  select plan_id from core.household_subscriptions
  where household_id = hh and status in ('active','trialing') and deleted_at is null
    and (ends_at is null or ends_at > now())
  order by starts_at desc limit 1 $$;
create function core.has_capability(hh uuid, cap text) returns boolean language sql stable security definer
set search_path = core, pg_temp as $$
  select exists (select 1 from core.plan_capabilities pc where pc.plan_id = core.active_plan(hh) and pc.capability_code = cap) $$;
create function core.limit_value(hh uuid, code text) returns int language sql stable security definer
set search_path = core, pg_temp as $$
  select limit_value from core.plan_limits where plan_id = core.active_plan(hh) and limit_code = code $$;
create function core.has_role(hh uuid, roles text[]) returns boolean language sql stable security definer
set search_path = core, pg_temp as $$
  select exists (select 1 from core.household_memberships m
    where m.household_id = hh and m.user_id = core.uid() and m.status = 'active'
      and m.deleted_at is null and m.role = any(roles)) $$;
create function core.is_member(hh uuid) returns boolean language sql stable as
$$ select core.has_role(hh, array['owner','admin','kitchen_manager','member','limited']) $$;

create function core.enforce_seat_limit() returns trigger language plpgsql as $$
declare lim int; cur int;
begin
  if new.status = 'removed' then return new; end if;
  lim := core.limit_value(new.household_id, 'user_seats');
  if lim is null then return new; end if;
  select count(*) into cur from core.household_memberships
   where household_id = new.household_id and status in ('active','invited')
     and deleted_at is null and id is distinct from new.id;
  if cur >= lim then
    raise exception 'seat_limit_reached' using errcode = 'P0001', hint = 'upgrade_required';
  end if;
  return new;
end $$;
create trigger trg_seat_limit before insert or update of status on core.household_memberships
  for each row execute function core.enforce_seat_limit();

create table core.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references core.users(id) on delete cascade,
  platform text not null check (platform in ('ios','android','web')),
  app_version text, last_seen_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);

-- ============================ CORE: CONSENT, AUDIT, DATA RIGHTS =======
create table core.consent_documents (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('terms','privacy','health_data')),
  version text not null, locale text not null default 'en-US',
  published_at timestamptz not null default now(),
  unique (kind, version, locale)
);
create table core.consent_records (       -- append-only evidence of consent
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references core.users(id),
  household_id uuid references core.households(id) on delete set null,
  document_id uuid not null references core.consent_documents(id),
  granted boolean not null,
  granted_at timestamptz not null default now(),
  platform text, app_version text
);
create table core.audit_log (             -- no health values, ids and actions only
  id bigserial primary key,
  at timestamptz not null default now(),
  household_id uuid, actor_user_id uuid,
  action text not null, entity text not null, entity_id uuid, meta jsonb
);
create index on core.audit_log (household_id, at desc);
create table core.data_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references core.users(id),
  household_id uuid,
  kind text not null check (kind in ('export','delete')),
  status text not null default 'requested' check (status in ('requested','processing','completed','rejected')),
  requested_at timestamptz not null default now(), completed_at timestamptz
);
create function core.audit() returns trigger language plpgsql security definer
set search_path = core, pg_temp as $$
declare j jsonb := to_jsonb(coalesce(new, old));
begin
  insert into core.audit_log(household_id, actor_user_id, action, entity, entity_id)
  values ((j->>'household_id')::uuid, core.uid(), tg_op, tg_table_schema||'.'||tg_table_name, (j->>'id')::uuid);
  return coalesce(new, old);
end $$;

-- ============================ REF: MASTER DATA ========================
create table ref.units (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, symbol text,
  dimension text not null check (dimension in ('mass','volume','count')),
  to_base numeric(18,8) not null check (to_base > 0),   -- grams / millilitres / each
  system text not null default 'us' check (system in ('us','metric','both')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.food_categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references ref.food_categories(id),
  code text not null unique, name text not null, sort_order int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.location_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null,
  temperature text not null default 'ambient' check (temperature in ('ambient','chilled','frozen')),
  is_container boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.appliance_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, category text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.utensil_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null,
  kind text not null check (kind in ('cookware','utensil','tool','container')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.nutrients (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, unit text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.allergens (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null,
  kind text not null check (kind in ('allergen','intolerance_trigger')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.food_items (             -- household_id null = system item; else household-custom item
  id uuid primary key default gen_random_uuid(),
  household_id uuid references core.households(id) on delete cascade,
  name text not null,
  category_id uuid references ref.food_categories(id),
  default_unit_id uuid references ref.units(id),
  default_location_type_id uuid references ref.location_types(id),
  shelf_life_days int check (shelf_life_days > 0),
  is_system boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create unique index uq_food_item_name on ref.food_items
  (coalesce(household_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)) where deleted_at is null;
create index ix_food_item_trgm on ref.food_items using gin (lower(name) gin_trgm_ops);
create table ref.food_item_aliases (
  id uuid primary key default gen_random_uuid(),
  food_item_id uuid not null references ref.food_items(id) on delete cascade,
  alias text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index ix_alias_trgm on ref.food_item_aliases using gin (lower(alias) gin_trgm_ops);
create table ref.food_item_allergens (
  food_item_id uuid not null references ref.food_items(id) on delete cascade,
  allergen_id uuid not null references ref.allergens(id),
  presence text not null default 'contains' check (presence in ('contains','may_contain')),
  primary key (food_item_id, allergen_id)
);
create table ref.food_item_nutrients (
  food_item_id uuid not null references ref.food_items(id) on delete cascade,
  nutrient_id uuid not null references ref.nutrients(id),
  amount_per_100g numeric(12,4) not null,
  primary key (food_item_id, nutrient_id)
);
create table ref.products (               -- Tier 2+ hook: branded products by GTIN (barcode). Unused in Basic.
  id uuid primary key default gen_random_uuid(),
  gtin text unique, brand text, name text not null,
  food_item_id uuid references ref.food_items(id),
  pack_quantity numeric(12,4), pack_unit_id uuid references ref.units(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.dietary_requirement_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, description text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.dietary_requirement_exclusions (   -- exactly one target per row
  id uuid primary key default gen_random_uuid(),
  requirement_type_id uuid not null references ref.dietary_requirement_types(id) on delete cascade,
  category_id uuid references ref.food_categories(id),
  food_item_id uuid references ref.food_items(id),
  allergen_id uuid references ref.allergens(id),
  check (num_nonnulls(category_id, food_item_id, allergen_id) = 1)
);
create table ref.health_requirement_types (         -- food requirements, not medical advice
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, description text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.health_requirement_rules (
  id uuid primary key default gen_random_uuid(),
  type_id uuid not null references ref.health_requirement_types(id) on delete cascade,
  nutrient_id uuid not null references ref.nutrients(id),
  comparator text not null check (comparator in ('max','min')),
  threshold_per_serving numeric(12,4) not null
);
create table ref.setup_steps (
  code text primary key, label text not null, sort_order int not null
);
create table ref.recipes (                -- household_id null = system recipe
  id uuid primary key default gen_random_uuid(),
  household_id uuid references core.households(id) on delete cascade,
  title text not null, description text,
  servings smallint not null default 4 check (servings > 0),
  prep_minutes smallint, cook_minutes smallint,
  steps jsonb not null default '[]',
  is_system boolean not null default false,
  is_published boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references ref.recipes(id) on delete cascade,
  food_item_id uuid not null references ref.food_items(id),
  quantity numeric(14,4) not null check (quantity >= 0),
  unit_id uuid not null references ref.units(id),
  qty_base numeric(18,4) not null default 0,       -- set by trigger
  is_optional boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index on ref.recipe_ingredients (recipe_id);
create table ref.recipe_appliance_requirements (
  recipe_id uuid not null references ref.recipes(id) on delete cascade,
  appliance_type_id uuid not null references ref.appliance_types(id),
  is_required boolean not null default true,
  primary key (recipe_id, appliance_type_id)
);
create table ref.recipe_utensil_requirements (
  recipe_id uuid not null references ref.recipes(id) on delete cascade,
  utensil_type_id uuid not null references ref.utensil_types(id),
  is_required boolean not null default false,
  primary key (recipe_id, utensil_type_id)
);
create table ref.recipe_nutrients (
  recipe_id uuid not null references ref.recipes(id) on delete cascade,
  nutrient_id uuid not null references ref.nutrients(id),
  amount_per_serving numeric(12,4) not null,
  primary key (recipe_id, nutrient_id)
);
create function ref.to_base(p_unit uuid, p_qty numeric) returns numeric language sql stable as
$$ select p_qty * to_base from ref.units where id = p_unit $$;
create function ref.set_recipe_qty_base() returns trigger language plpgsql as
$$ begin new.qty_base := ref.to_base(new.unit_id, new.quantity); return new; end $$;
create trigger trg_qty_base before insert or update on ref.recipe_ingredients
  for each row execute function ref.set_recipe_qty_base();
create function ref.category_ancestors(p_cat uuid) returns table(id uuid) language sql stable as $$
  with recursive a as (
    select c.id, c.parent_id from ref.food_categories c where c.id = p_cat
    union all select c.id, c.parent_id from ref.food_categories c join a on a.parent_id = c.id)
  select id from a $$;

-- ============================ HH: HOUSEHOLD OPERATIONAL DATA ==========
create table hh.household_settings (
  household_id uuid primary key references core.households(id) on delete cascade,
  use_soon_days smallint not null default 3 check (use_soon_days >= 0),
  low_stock_alerts boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.family_members (          -- a PROFILE, not a login. Optional link to an account.
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  user_id uuid references core.users(id),
  preferred_name text not null,
  relationship text not null default 'other' check (relationship in
    ('self','spouse_partner','parent','child','sibling','grandparent','caregiver','other')),
  birth_date date, age_range text, sex text, avatar_url text,
  is_account_holder boolean not null default false,
  unique (household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create unique index uq_member_user on hh.family_members(household_id, user_id) where user_id is not null and deleted_at is null;
create table hh.kitchens (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  name text not null default 'Main Kitchen', is_primary boolean not null default true,
  unique (household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.locations (               -- Pantry > Shelf 1..n, Refrigerator > Drawer, etc.
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  kitchen_id uuid not null,
  parent_id uuid,
  location_type_id uuid not null references ref.location_types(id),
  name text not null, sort_order int not null default 0,
  unique (household_id, id),
  foreign key (household_id, kitchen_id) references hh.kitchens(household_id, id) on delete cascade,
  foreign key (household_id, parent_id) references hh.locations(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index on hh.locations (household_id, parent_id);
create table hh.household_appliances (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  appliance_type_id uuid not null references ref.appliance_types(id),
  nickname text, location_id uuid, quantity smallint not null default 1 check (quantity > 0),
  status text not null default 'active' check (status in ('active','broken','retired')),
  foreign key (household_id, location_id) references hh.locations(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.household_utensils (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  utensil_type_id uuid not null references ref.utensil_types(id),
  nickname text, quantity smallint check (quantity > 0), location_id uuid,
  foreign key (household_id, location_id) references hh.locations(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.household_item_settings (
  household_id uuid not null references core.households(id) on delete cascade,
  food_item_id uuid not null references ref.food_items(id),
  par_level_base numeric(18,4), low_stock_base numeric(18,4),
  primary key (household_id, food_item_id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.inventory_items (         -- one row per stock lot; qty_base is maintained ONLY by the ledger
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  food_item_id uuid not null references ref.food_items(id),
  product_id uuid references ref.products(id),
  location_id uuid,
  display_unit_id uuid not null references ref.units(id),
  qty_base numeric(18,4) not null default 0 check (qty_base >= 0),
  brand text, purchase_date date, best_by_date date, expiration_date date, notes text,
  status text not null default 'active' check (status in ('active','consumed','discarded','expired')),
  created_source text not null default 'manual'
    check (created_source in ('manual','barcode','receipt','image','video','import')),
  unique (household_id, id),
  foreign key (household_id, location_id) references hh.locations(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index on hh.inventory_items (household_id, food_item_id) where status = 'active';
create index on hh.inventory_items (household_id, expiration_date) where status = 'active';
create table hh.meal_logs (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  recipe_id uuid references ref.recipes(id),
  title text not null,
  meal_type text check (meal_type in ('breakfast','lunch','dinner','snack','other')),
  cooked_at timestamptz not null default now(), servings numeric(6,2), notes text,
  unique (household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.meal_log_participants (
  household_id uuid not null,
  meal_log_id uuid not null, member_id uuid not null,
  consumed boolean not null default true, portion numeric(4,2) not null default 1,
  primary key (meal_log_id, member_id),
  foreign key (household_id, meal_log_id) references hh.meal_logs(household_id, id) on delete cascade,
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.meal_plan_entries (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  plan_date date not null,
  meal_type text check (meal_type in ('breakfast','lunch','dinner','snack','other')),
  recipe_id uuid references ref.recipes(id), title text,
  status text not null default 'planned' check (status in ('planned','cooked','skipped')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  name text not null default 'Grocery List',
  status text not null default 'open' check (status in ('open','done')),
  unique (household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.shopping_list_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, list_id uuid not null,
  food_item_id uuid references ref.food_items(id), custom_name text,
  quantity numeric(14,4), unit_id uuid references ref.units(id),
  status text not null default 'open' check (status in ('open','bought')),
  source text not null default 'manual' check (source in ('manual','low_stock','recipe')),
  check (food_item_id is not null or custom_name is not null),
  foreign key (household_id, list_id) references hh.shopping_lists(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table hh.alerts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  kind text not null check (kind in ('use_soon','low_stock','allergen_conflict','system')),
  entity text, entity_id uuid, status text not null default 'open' check (status in ('open','dismissed','resolved')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);

-- Append-only inventory ledger: every quantity change is a row
create table hh.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  inventory_item_id uuid not null,
  kind text not null check (kind in ('add','purchase','use','consume','discard','adjust','transfer_in','transfer_out')),
  quantity numeric(14,4) not null,          -- entered amount in unit_id (negative only for 'adjust')
  unit_id uuid not null references ref.units(id),
  qty_base numeric(18,4) not null default 0, -- signed, set by trigger
  meal_log_id uuid, shopping_list_item_id uuid, capture_detection_id uuid,
  device_id uuid, created_by uuid references core.users(id),
  occurred_at timestamptz not null default now(), note text,
  check (kind = 'adjust' or quantity > 0),
  foreign key (household_id, inventory_item_id) references hh.inventory_items(household_id, id) on delete cascade,
  foreign key (household_id, meal_log_id) references hh.meal_logs(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index on hh.inventory_transactions (household_id, inventory_item_id, occurred_at);
create function hh.prepare_tx() returns trigger language plpgsql as $$
declare f numeric := ref.to_base(new.unit_id, 1);
begin
  new.created_by := coalesce(new.created_by, core.uid());
  new.qty_base := case when new.kind in ('use','consume','discard','transfer_out') then -1 else 1 end * new.quantity * f;
  return new;
end $$;
create trigger trg_prepare before insert on hh.inventory_transactions for each row execute function hh.prepare_tx();
create function hh.apply_tx() returns trigger language plpgsql security definer set search_path = hh, pg_temp as $$
begin
  update hh.inventory_items i set
    qty_base = i.qty_base + new.qty_base,
    status = case when i.qty_base + new.qty_base <= 0
                  then case new.kind when 'discard' then 'discarded' else 'consumed' end
                  else 'active' end
  where i.id = new.inventory_item_id and i.household_id = new.household_id;
  return new;
end $$;
create trigger trg_apply after insert on hh.inventory_transactions for each row execute function hh.apply_tx();
create function hh.block_tx_update() returns trigger language plpgsql as
$$ begin raise exception 'inventory_transactions is append-only; post an adjust row instead'; end $$;
create trigger trg_immutable before update on hh.inventory_transactions for each row execute function hh.block_tx_update();

-- ============================ HEALTH: MEMBER FOOD REQUIREMENTS ========
-- Each class is its own table so the UI/engine never confuses a preference with an allergy.
create table health.member_allergies (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, member_id uuid not null,
  allergen_id uuid not null references ref.allergens(id),
  severity text not null default 'unknown' check (severity in ('mild','moderate','severe','unknown')), notes text,
  unique (member_id, allergen_id),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table health.member_intolerances (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, member_id uuid not null,
  allergen_id uuid not null references ref.allergens(id), notes text,
  unique (member_id, allergen_id),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table health.member_dietary_requirements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, member_id uuid not null,
  requirement_type_id uuid not null references ref.dietary_requirement_types(id), notes text,
  unique (member_id, requirement_type_id),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table health.member_health_requirements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, member_id uuid not null,
  health_requirement_type_id uuid not null references ref.health_requirement_types(id), notes text,
  unique (member_id, health_requirement_type_id),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table health.member_food_preferences (   -- like / dislike / avoid / prioritize (user choices, not medical)
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, member_id uuid not null,
  kind text not null check (kind in ('like','dislike','avoid','prioritize')),
  category_id uuid references ref.food_categories(id),
  food_item_id uuid references ref.food_items(id),
  check (num_nonnulls(category_id, food_item_id) = 1),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);

-- ============================ CAPTURE (Tier 2+ extension) =============
create table capture.capture_sessions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  kind text not null check (kind in ('image','video','barcode','receipt')),
  status text not null default 'open' check (status in ('open','processing','review','completed','failed')),
  location_id uuid, device_id uuid, created_by uuid references core.users(id) default core.uid(),
  unique (household_id, id),
  foreign key (household_id, location_id) references hh.locations(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table capture.capture_assets (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, session_id uuid not null,
  storage_key text not null, mime_type text, bytes bigint, sha256 text,
  foreign key (household_id, session_id) references capture.capture_sessions(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table capture.capture_detections (  -- proposed items awaiting user confirmation
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, session_id uuid not null,
  food_item_id uuid references ref.food_items(id), product_id uuid references ref.products(id),
  label text, confidence numeric(4,3), qty_guess numeric(14,4), unit_id uuid references ref.units(id),
  state text not null default 'proposed' check (state in ('proposed','accepted','rejected')),
  inventory_item_id uuid,
  unique (household_id, id),
  foreign key (household_id, session_id) references capture.capture_sessions(household_id, id) on delete cascade,
  foreign key (household_id, inventory_item_id) references hh.inventory_items(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
alter table hh.inventory_transactions add constraint fk_tx_detection
  foreign key (household_id, capture_detection_id) references capture.capture_detections(household_id, id);
create function capture.require_capability() returns trigger language plpgsql as $$
declare cap text := case new.kind when 'image' then 'inventory.capture.image' when 'video' then 'inventory.capture.video'
                    when 'barcode' then 'inventory.scan.barcode' else 'inventory.scan.receipt' end;
begin
  if not core.has_capability(new.household_id, cap) then
    raise exception 'capability_required' using errcode = 'P0001', hint = cap;
  end if;
  return new;
end $$;
create trigger trg_cap before insert on capture.capture_sessions for each row execute function capture.require_capability();

-- ============================ MATCH: EXPLAINABLE RECOMMENDATIONS ======
create table match.recommendation_runs (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  requested_by uuid references core.users(id) default core.uid(),
  member_ids uuid[] not null, engine_version text not null default 'v1',
  unique (household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table match.recommendation_results (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, run_id uuid not null,
  recipe_id uuid not null references ref.recipes(id),
  fit_score int not null check (fit_score between 0 and 100),
  availability_pct int not null, blocked boolean not null, reasons jsonb not null default '[]',
  foreign key (household_id, run_id) references match.recommendation_runs(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);

-- ---- The matching engine: inventory + appliances + each member's requirements ----
create function match.match_recipes(p_household uuid, p_members uuid[] default null)
returns table (recipe_id uuid, title text, fit_score int, availability_pct int, blocked boolean, reasons jsonb)
language sql stable as $$
with
mem as (select m.id, m.preferred_name as nm from hh.family_members m
        where m.household_id = p_household and m.deleted_at is null and (p_members is null or m.id = any(p_members))),
cand as (select r.id, r.title from ref.recipes r
         where r.deleted_at is null and r.is_published and (r.household_id is null or r.household_id = p_household)),
stock as (select i.food_item_id, sum(i.qty_base) as q from hh.inventory_items i
          where i.household_id = p_household and i.deleted_at is null and i.status = 'active'
            and (i.expiration_date is null or i.expiration_date >= current_date) group by i.food_item_id),
ing as (select ri.recipe_id, ri.food_item_id, fi.name as item, fi.category_id, ri.qty_base, ri.is_optional,
               coalesce(s.q, 0) as onhand
        from ref.recipe_ingredients ri join cand c on c.id = ri.recipe_id
        join ref.food_items fi on fi.id = ri.food_item_id
        left join stock s on s.food_item_id = ri.food_item_id where ri.deleted_at is null),
avail as (select recipe_id,
          round(100 * avg(case when qty_base > 0 then least(1, onhand / qty_base) when onhand > 0 then 1 else 0 end))::int as pct
          from ing where not is_optional group by recipe_id),
ev as (
  select i.recipe_id, 'allergy'::text as type, 'block'::text as severity, m.nm::text as member, ('contains ' || a.name)::text as detail
    from ing i join ref.food_item_allergens fa on fa.food_item_id = i.food_item_id
    join ref.allergens a on a.id = fa.allergen_id
    join health.member_allergies x on x.allergen_id = fa.allergen_id and x.deleted_at is null
    join mem m on m.id = x.member_id
  union all
  select i.recipe_id, 'intolerance', 'warn', m.nm, 'contains ' || a.name
    from ing i join ref.food_item_allergens fa on fa.food_item_id = i.food_item_id
    join ref.allergens a on a.id = fa.allergen_id
    join health.member_intolerances x on x.allergen_id = fa.allergen_id and x.deleted_at is null
    join mem m on m.id = x.member_id
  union all
  select i.recipe_id, 'diet', 'block', m.nm, t.name || ': ' || i.item
    from ing i join health.member_dietary_requirements d on d.deleted_at is null
    join mem m on m.id = d.member_id
    join ref.dietary_requirement_types t on t.id = d.requirement_type_id
    join ref.dietary_requirement_exclusions x on x.requirement_type_id = t.id
    where x.food_item_id = i.food_item_id
       or exists (select 1 from ref.category_ancestors(i.category_id) ca where ca.id = x.category_id)
       or exists (select 1 from ref.food_item_allergens fa where fa.food_item_id = i.food_item_id and fa.allergen_id = x.allergen_id)
  union all
  select rn.recipe_id, 'health', 'warn', m.nm, ht.name || ': ' || n.name
    from health.member_health_requirements h join mem m on m.id = h.member_id
    join ref.health_requirement_types ht on ht.id = h.health_requirement_type_id
    join ref.health_requirement_rules hr on hr.type_id = ht.id
    join ref.recipe_nutrients rn on rn.nutrient_id = hr.nutrient_id
    join cand c on c.id = rn.recipe_id join ref.nutrients n on n.id = hr.nutrient_id
    where h.deleted_at is null and ((hr.comparator = 'max' and rn.amount_per_serving > hr.threshold_per_serving)
       or (hr.comparator = 'min' and rn.amount_per_serving < hr.threshold_per_serving))
  union all
  select ra.recipe_id, 'appliance', 'block', null, 'needs ' || at.name
    from ref.recipe_appliance_requirements ra join cand c on c.id = ra.recipe_id
    join ref.appliance_types at on at.id = ra.appliance_type_id
    where ra.is_required and not exists (select 1 from hh.household_appliances ha
      where ha.household_id = p_household and ha.appliance_type_id = ra.appliance_type_id
        and ha.status = 'active' and ha.deleted_at is null)
  union all
  select i.recipe_id, 'preference', case p.kind when 'avoid' then 'block' when 'dislike' then 'warn' else 'good' end,
         m.nm, p.kind || ': ' || i.item
    from ing i join health.member_food_preferences p on p.deleted_at is null
    join mem m on m.id = p.member_id
    where p.food_item_id = i.food_item_id
       or exists (select 1 from ref.category_ancestors(i.category_id) ca where ca.id = p.category_id)
  union all
  select recipe_id, 'missing', 'info', null, item from ing
    where not is_optional and onhand < greatest(qty_base, 0.0001)
),
agg as (select recipe_id, bool_or(severity = 'block') as blocked,
        count(*) filter (where severity = 'warn') as warns, count(*) filter (where severity = 'good') as goods,
        jsonb_agg(jsonb_build_object('type', type, 'severity', severity, 'member', member, 'detail', detail)
                  order by severity, type) as reasons
        from (select distinct * from ev) e group by recipe_id)
select c.id, c.title,
  case when coalesce(g.blocked, false) then 0
       else greatest(0, least(100, round(0.7 * coalesce(av.pct, 100) + 30 - 8 * coalesce(g.warns, 0) + 4 * coalesce(g.goods, 0))))::int end,
  coalesce(av.pct, 100), coalesce(g.blocked, false), coalesce(g.reasons, '[]'::jsonb)
from cand c left join avail av on av.recipe_id = c.id left join agg g on g.recipe_id = c.id
order by 5, 3 desc, 2 $$;

-- ============================ VIEWS (RLS-respecting) ==================
create view hh.v_inventory_current with (security_invoker = true) as
  select i.*, fi.name as food_name, fi.category_id from hh.inventory_items i
  join ref.food_items fi on fi.id = i.food_item_id where i.status = 'active' and i.deleted_at is null;
create view hh.v_use_soon with (security_invoker = true) as
  select v.id, v.household_id, v.food_name, v.location_id, coalesce(v.expiration_date, v.best_by_date) as due_date,
         coalesce(v.expiration_date, v.best_by_date) - current_date as days_left
  from hh.v_inventory_current v left join hh.household_settings s on s.household_id = v.household_id
  where v.qty_base > 0 and coalesce(v.expiration_date, v.best_by_date) <= current_date + coalesce(s.use_soon_days, 3);
create view hh.v_low_stock with (security_invoker = true) as
  select i.household_id, i.food_item_id, i.food_name, sum(i.qty_base) as on_hand_base, s.low_stock_base
  from hh.v_inventory_current i join hh.household_item_settings s
    on s.household_id = i.household_id and s.food_item_id = i.food_item_id and s.deleted_at is null
  group by i.household_id, i.food_item_id, i.food_name, s.low_stock_base having sum(i.qty_base) <= s.low_stock_base;
create view health.v_member_constraints with (security_invoker = true) as
  select household_id, member_id, 'allergy' as class, allergen_id as ref_id from health.member_allergies where deleted_at is null
  union all select household_id, member_id, 'intolerance', allergen_id from health.member_intolerances where deleted_at is null
  union all select household_id, member_id, 'diet', requirement_type_id from health.member_dietary_requirements where deleted_at is null
  union all select household_id, member_id, 'health', health_requirement_type_id from health.member_health_requirements where deleted_at is null;

-- ============================ SETUP RPCs (answers -> records) =========
create table core.setup_progress (
  household_id uuid not null references core.households(id) on delete cascade,
  step_code text not null references ref.setup_steps(code),
  status text not null default 'pending' check (status in ('pending','in_progress','done','skipped')),
  completed_at timestamptz,
  primary key (household_id, step_code),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create function core.create_household(p_user uuid, p_name text, p_country char(2) default 'US',
  p_region text default null, p_timezone text default null, p_people int default null)
returns uuid language plpgsql security definer set search_path = core, hh, ref, pg_temp as $$
declare v_hh uuid; v_plan smallint; v_u core.users; v_lim int;
begin
  if core.uid() is not null and core.uid() <> p_user then raise exception 'forbidden'; end if;
  select * into v_u from core.users where id = p_user;
  if not found then raise exception 'user_not_found'; end if;
  select id into v_plan from core.plans where code = 'basic';
  select limit_value into v_lim from core.plan_limits where plan_id = v_plan and limit_code = 'households_per_owner';
  if v_lim is not null and (select count(*) from core.households where owner_user_id = p_user and deleted_at is null) >= v_lim then
    raise exception 'household_limit_reached' using hint = 'upgrade_required';
  end if;
  insert into core.households(name, country_code, region_code, timezone, people_count, owner_user_id)
    values (p_name, p_country, p_region, p_timezone, p_people, p_user) returning id into v_hh;
  insert into core.household_subscriptions(household_id, plan_id, source) values (v_hh, v_plan, 'free');
  insert into core.household_memberships(household_id, user_id, role) values (v_hh, p_user, 'owner');
  insert into hh.kitchens(household_id) values (v_hh);
  insert into hh.household_settings(household_id) values (v_hh);
  insert into hh.family_members(household_id, user_id, preferred_name, relationship, is_account_holder)
    values (v_hh, p_user, coalesce(v_u.first_name, 'Me'), 'self', true);
  insert into core.setup_progress(household_id, step_code, status, completed_at)
    select v_hh, code, case when code = 'household' then 'done' else 'pending' end,
           case when code = 'household' then now() end from ref.setup_steps;
  return v_hh;
end $$;

create function hh.setup_storage(p_household uuid, p_type text, p_name text default null, p_shelves int default 0)
returns uuid language plpgsql set search_path = hh, ref, core, pg_temp as $$
declare v_k uuid; v_t uuid; v_id uuid; v_name text; i int;
begin
  select id into v_k from hh.kitchens where household_id = p_household and is_primary and deleted_at is null limit 1;
  select id, name into v_t, v_name from ref.location_types where code = p_type;
  if v_t is null then raise exception 'unknown_location_type'; end if;
  v_name := coalesce(p_name, v_name);
  select id into v_id from hh.locations where household_id = p_household and kitchen_id = v_k
    and location_type_id = v_t and name = v_name and parent_id is null and deleted_at is null;
  if v_id is null then
    insert into hh.locations(household_id, kitchen_id, location_type_id, name) values (p_household, v_k, v_t, v_name) returning id into v_id;
    for i in 1..coalesce(p_shelves, 0) loop
      insert into hh.locations(household_id, kitchen_id, parent_id, location_type_id, name, sort_order)
        values (p_household, v_k, v_id, (select id from ref.location_types where code = 'shelf'), 'Shelf ' || i, i);
    end loop;
  end if;
  return v_id;
end $$;

create function hh.setup_appliances(p_household uuid, p_codes text[]) returns int
language plpgsql set search_path = hh, ref, pg_temp as $$
declare n int;
begin
  insert into hh.household_appliances(household_id, appliance_type_id)
    select p_household, t.id from ref.appliance_types t
    where t.code = any(p_codes) and not exists (select 1 from hh.household_appliances a
      where a.household_id = p_household and a.appliance_type_id = t.id and a.deleted_at is null);
  get diagnostics n = row_count; return n;
end $$;

create function hh.setup_utensils(p_household uuid, p_codes text[]) returns int
language plpgsql set search_path = hh, ref, pg_temp as $$
declare n int;
begin
  insert into hh.household_utensils(household_id, utensil_type_id)
    select p_household, t.id from ref.utensil_types t
    where t.code = any(p_codes) and not exists (select 1 from hh.household_utensils a
      where a.household_id = p_household and a.utensil_type_id = t.id and a.deleted_at is null);
  get diagnostics n = row_count; return n;
end $$;

create function hh.add_inventory(p_household uuid, p_food_name text, p_qty numeric, p_unit text,
  p_location uuid default null, p_best_by date default null, p_expiration date default null,
  p_brand text default null, p_notes text default null)
returns uuid language plpgsql set search_path = hh, ref, core, pg_temp as $$
declare v_food uuid; v_unit uuid; v_item uuid;
begin
  select id into v_unit from ref.units where code = p_unit;
  if v_unit is null then raise exception 'unknown_unit'; end if;
  select id into v_food from ref.food_items where lower(name) = lower(trim(p_food_name))
    and (household_id is null or household_id = p_household) and deleted_at is null
    order by household_id nulls last limit 1;
  if v_food is null then
    insert into ref.food_items(household_id, name, default_unit_id) values (p_household, trim(p_food_name), v_unit) returning id into v_food;
  end if;
  insert into hh.inventory_items(household_id, food_item_id, location_id, display_unit_id, brand, best_by_date, expiration_date, notes)
    values (p_household, v_food, p_location, v_unit, p_brand, p_best_by, p_expiration, p_notes) returning id into v_item;
  insert into hh.inventory_transactions(household_id, inventory_item_id, kind, quantity, unit_id)
    values (p_household, v_item, 'add', p_qty, v_unit);
  return v_item;
end $$;

-- ============================ TRIGGERS, RLS, GRANTS ===================
do $$ declare r record; begin
  for r in select c.table_schema s, c.table_name t from information_schema.columns c
           join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
           where c.column_name = 'rev' loop
    execute format('create trigger trg_touch before insert or update on %I.%I for each row execute function core.touch()', r.s, r.t);
  end loop;
  for r in select unnest(array['health.member_allergies','health.member_intolerances','health.member_dietary_requirements',
      'health.member_health_requirements','health.member_food_preferences','core.household_memberships','core.households',
      'core.household_subscriptions','hh.family_members']) t loop
    execute format('create trigger trg_audit after insert or update or delete on %s for each row execute function core.audit()', r.t);
  end loop;
end $$;

do $$ declare r record; begin
  create role wam_app nologin;
exception when duplicate_object then null; end $$;

do $$ declare r record; begin
  -- tenant tables: hh / capture / match
  for r in select c.table_schema s, c.table_name t from information_schema.columns c
           join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
           where c.column_name = 'household_id' and c.table_schema in ('hh','capture','match') and c.table_name <> 'inventory_transactions' loop
    execute format('alter table %I.%I enable row level security', r.s, r.t);
    execute format('create policy tenant_all on %I.%I using (core.is_member(household_id)) with check (core.is_member(household_id))', r.s, r.t);
  end loop;
  -- health: members except "limited" role
  for r in select table_name t from information_schema.tables where table_schema = 'health' and table_type = 'BASE TABLE' loop
    execute format('alter table health.%I enable row level security', r.t);
    execute format($p$create policy health_access on health.%I using (core.has_role(household_id, array['owner','admin','kitchen_manager','member']))
      with check (core.has_role(household_id, array['owner','admin','kitchen_manager','member']))$p$, r.t);
  end loop;
  -- ref: readable by all; household-custom rows writable by that household
  for r in select table_name t from information_schema.tables where table_schema = 'ref' and table_type = 'BASE TABLE' loop
    execute format('alter table ref.%I enable row level security', r.t);
    if exists (select 1 from information_schema.columns where table_schema = 'ref' and table_name = r.t and column_name = 'household_id') then
      execute format('create policy ref_read on ref.%I for select using (household_id is null or core.is_member(household_id))', r.t);
      execute format('create policy ref_write on ref.%I for all using (household_id is not null and core.is_member(household_id)) with check (household_id is not null and core.is_member(household_id))', r.t);
    else
      execute format('create policy ref_read on ref.%I for select using (true)', r.t);
    end if;
  end loop;
end $$;
alter table hh.inventory_transactions enable row level security;
create policy tx_read on hh.inventory_transactions for select using (core.is_member(household_id));
create policy tx_insert on hh.inventory_transactions for insert with check (core.is_member(household_id));

do $$ declare t text; begin
  foreach t in array array['users','households','household_subscriptions','household_memberships','devices','consent_documents',
    'consent_records','audit_log','data_requests','setup_progress','plans','capabilities','plan_capabilities','plan_limits'] loop
    execute format('alter table core.%I enable row level security', t);
  end loop;
end $$;
create policy p_read on core.plans for select using (true);
create policy p_read on core.capabilities for select using (true);
create policy p_read on core.plan_capabilities for select using (true);
create policy p_read on core.plan_limits for select using (true);
create policy p_read on core.consent_documents for select using (true);
create policy u_self on core.users for all using (id = core.uid()) with check (id = core.uid());
create policy h_read on core.households for select using (core.is_member(id));
create policy h_upd on core.households for update using (core.has_role(id, array['owner','admin']));
create policy s_read on core.household_subscriptions for select using (core.is_member(household_id));
create policy m_read on core.household_memberships for select using (core.is_member(household_id));
create policy m_write on core.household_memberships for all using (core.has_role(household_id, array['owner','admin']))
  with check (core.has_role(household_id, array['owner','admin']));
create policy d_self on core.devices for all using (user_id = core.uid()) with check (user_id = core.uid());
create policy c_self on core.consent_records for all using (user_id = core.uid()) with check (user_id = core.uid());
create policy a_read on core.audit_log for select using (household_id is not null and core.has_role(household_id, array['owner','admin']));
create policy dr_self on core.data_requests for all using (user_id = core.uid()) with check (user_id = core.uid());
create policy sp_all on core.setup_progress for all using (core.is_member(household_id)) with check (core.is_member(household_id));

grant usage on schema core, ref, hh, health, capture, match to wam_app;
grant select, insert, update, delete on all tables in schema core, ref, hh, health, capture, match to wam_app;
grant usage on all sequences in schema core to wam_app;
grant execute on all functions in schema core, ref, hh, capture, match to wam_app;
