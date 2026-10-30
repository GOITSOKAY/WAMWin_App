-- =====================================================================
-- 08_kitchen_catalog.sql — Kitchen inventory: MASTER catalog + DETAIL records
--   FOOD:           ref.food_items (master)         -> hh.inventory_items + ledger (detail)
--   KITCHEN ITEMS:  ref.kitchen_item_types (master) -> hh.kitchen_items (detail)
--     covers appliances, food storage, cookware, bakeware, utensils, cutlery,
--     dinnerware, glassware, serveware, facilities and cleaning items
--   PLACES:         ref.location_types (master)     -> hh.locations (detail)
-- Every master item is classified by TYPE (ref.item_classes tree) and by USE
-- (ref.item_uses). A household may have several kitchens in different countries.
-- =====================================================================
-- ---- Kitchens in different regions (a family spread across continents) ----
alter table hh.kitchens add column country_code char(2), add column region_code text, add column timezone text,
  add column measurement_system text check (measurement_system in ('us','metric')), add column locale text;
create unique index uq_primary_kitchen on hh.kitchens(household_id) where is_primary and deleted_at is null;
create function hh.kitchen_defaults() returns trigger language plpgsql as $$
declare h core.households;
begin
  select * into h from core.households where id = new.household_id;
  new.country_code := coalesce(new.country_code, h.country_code);
  new.region_code := coalesce(new.region_code, h.region_code);
  new.timezone := coalesce(new.timezone, h.timezone);
  new.measurement_system := coalesce(new.measurement_system, h.measurement_system);
  new.locale := coalesce(new.locale, h.locale);
  return new;
end $$;
create trigger trg_defaults before insert on hh.kitchens for each row execute function hh.kitchen_defaults();
create table hh.member_kitchens (            -- which kitchens each family member eats from / lives with
  household_id uuid not null, member_id uuid not null, kitchen_id uuid not null,
  is_home boolean not null default false,
  primary key (member_id, kitchen_id),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  foreign key (household_id, kitchen_id) references hh.kitchens(household_id, id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create unique index uq_member_home_kitchen on hh.member_kitchens(member_id) where is_home and deleted_at is null;

-- ---- Places: size and capacity ----
alter table hh.locations add column size_label text, add column capacity_value numeric(12,3), add column capacity_unit_id uuid references ref.units(id);
insert into ref.location_types(code, name, temperature) values
 ('china_cabinet','China Cabinet / Hutch','ambient'),('sideboard','Sideboard / Buffet','ambient'),('wine_rack','Wine Rack','ambient'),
 ('bar_cart','Bar Cart','ambient'),('pot_rack','Pot Rack','ambient'),('lazy_susan','Lazy Susan Cabinet','ambient'),
 ('utility_closet','Utility Closet','ambient'),('cellar','Cellar','chilled') on conflict (code) do nothing;
insert into ref.units(code, name, symbol, dimension, to_base, system) values
 ('dozen','dozen','doz','count',12,'both'),('pack','pack','pack','count',1,'both'),('can','can','can','count',1,'both'),
 ('bottle','bottle','btl','count',1,'both'),('bunch','bunch','bunch','count',1,'both') on conflict (code) do nothing;

-- ---- Localised labels for ANY master record (food, item types, questions, classes) ----
create table ref.i18n_labels (
  entity text not null, entity_id uuid not null, field text not null default 'name', locale text not null, value text not null,
  primary key (entity, entity_id, field, locale),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create function ref.label(p_entity text, p_id uuid, p_locale text, p_fallback text, p_field text default 'name')
returns text language sql stable as $$
  select coalesce(
    (select value from ref.i18n_labels where entity = p_entity and entity_id = p_id and field = p_field and locale = p_locale and deleted_at is null),
    (select value from ref.i18n_labels where entity = p_entity and entity_id = p_id and field = p_field and locale = split_part(p_locale, '-', 1) and deleted_at is null),
    p_fallback) $$;

-- ---- Classification: TYPE tree + USE tags ----
create table ref.item_classes (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references ref.item_classes(id),
  code text not null unique, name text not null, sort_order int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.item_uses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null,
  use_group text not null check (use_group in ('cooking','prep','storage','serving','drinking','dining','cleaning','safety','other')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.materials (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.kitchen_item_types (        -- MASTER FILE for every non-food kitchen item
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references ref.item_classes(id),
  code text not null unique, name text not null, description text,
  capacity_dimension text not null default 'none' check (capacity_dimension in ('volume','mass','count','none')),
  appliance_type_id uuid references ref.appliance_types(id),     -- links items that recipes can require
  is_common boolean not null default true,
  regions text[],                                                 -- ISO countries where it is commonly asked about; null = everywhere
  sort_order int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index on ref.kitchen_item_types (class_id);
create table ref.kitchen_item_type_uses (    -- one primary use, any number of secondary uses
  type_id uuid not null references ref.kitchen_item_types(id) on delete cascade,
  use_id uuid not null references ref.item_uses(id),
  is_primary boolean not null default false,
  primary key (type_id, use_id)
);
create unique index uq_one_primary_use on ref.kitchen_item_type_uses(type_id) where is_primary;
create table ref.kitchen_item_sizes (        -- standard sizes offered when the user is asked "what size?"
  id uuid primary key default gen_random_uuid(),
  type_id uuid not null references ref.kitchen_item_types(id) on delete cascade,
  code text not null, label text not null,
  capacity_value numeric(12,3), capacity_unit_id uuid references ref.units(id), sort_order int not null default 0,
  unique (type_id, code),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.food_item_packages (        -- typical package sizes, which differ by country
  id uuid primary key default gen_random_uuid(),
  food_item_id uuid not null references ref.food_items(id) on delete cascade,
  country_code char(2), label text not null,
  size_qty numeric(14,4) not null, unit_id uuid not null references ref.units(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);

create function ref.class_descendants(p uuid) returns setof uuid language sql stable as $$
  with recursive d as (select id from ref.item_classes where id = p
    union all select c.id from ref.item_classes c join d on c.parent_id = d.id) select id from d $$;
create function ref.class_path(p uuid) returns text language sql stable as $$
  with recursive a as (select id, parent_id, name, 1 as depth from ref.item_classes where id = p
    union all select c.id, c.parent_id, c.name, a.depth + 1 from ref.item_classes c join a on a.parent_id = c.id)
  select string_agg(name, ' > ' order by depth desc) from a $$;

-- ---- DETAIL FILE: what this household actually owns ----
create table hh.kitchen_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references core.households(id) on delete cascade,
  kitchen_id uuid, location_id uuid,
  item_type_id uuid not null references ref.kitchen_item_types(id),
  size_id uuid references ref.kitchen_item_sizes(id),
  quantity int not null default 1 check (quantity > 0),
  set_pieces int check (set_pieces > 0),                    -- e.g. a 12-piece dinner set
  nickname text, brand text, model text,
  material_id uuid references ref.materials(id), color text,
  capacity_value numeric(12,3) check (capacity_value > 0), capacity_unit_id uuid references ref.units(id),
  length_cm numeric(8,2), width_cm numeric(8,2), height_cm numeric(8,2),
  power_watts int check (power_watts > 0),
  acquired_on date,
  condition text not null default 'good' check (condition in ('new','good','worn','needs_repair')),
  status text not null default 'active' check (status in ('active','broken','retired')),
  is_built_in boolean not null default false,
  notes text,
  unique (household_id, id),
  foreign key (household_id, kitchen_id) references hh.kitchens(household_id, id),
  foreign key (household_id, location_id) references hh.locations(household_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create index on hh.kitchen_items (household_id, kitchen_id, item_type_id) where deleted_at is null;

-- ---- Food detail: regional naming, pack sizes, opened date; every record belongs to a kitchen ----
alter table hh.inventory_items add column kitchen_id uuid, add column pack_size numeric(14,4),
  add column pack_unit_id uuid references ref.units(id), add column pack_count int check (pack_count > 0), add column opened_on date;
alter table hh.inventory_items add constraint fk_inv_kitchen foreign key (household_id, kitchen_id) references hh.kitchens(household_id, id);
create index on hh.inventory_items (household_id, kitchen_id) where status = 'active';
create function hh.default_kitchen() returns trigger language plpgsql as $$
declare lk uuid;
begin
  if new.location_id is not null then
    select kitchen_id into lk from hh.locations where household_id = new.household_id and id = new.location_id;
    if new.kitchen_id is not null and lk is not null and lk <> new.kitchen_id then raise exception 'location_kitchen_mismatch'; end if;
    new.kitchen_id := coalesce(new.kitchen_id, lk);
  end if;
  if new.kitchen_id is null then
    select id into new.kitchen_id from hh.kitchens where household_id = new.household_id and is_primary and deleted_at is null limit 1;
  end if;
  return new;
end $$;
create trigger trg_kitchen before insert or update of location_id, kitchen_id on hh.inventory_items for each row execute function hh.default_kitchen();
create trigger trg_kitchen before insert or update of location_id, kitchen_id on hh.kitchen_items for each row execute function hh.default_kitchen();

-- ---- Views ----
create view hh.v_kitchen_items_classified with (security_invoker = true) as
  select ki.id, ki.household_id, ki.kitchen_id, ki.location_id, ki.quantity, ki.nickname, ki.brand, ki.condition, ki.status,
         t.code as type_code, t.name as type_name, ref.class_path(t.class_id) as class_path,
         (select u.name from ref.kitchen_item_type_uses tu join ref.item_uses u on u.id = tu.use_id
           where tu.type_id = t.id and tu.is_primary) as primary_use,
         (select string_agg(u.name, ', ' order by u.name) from ref.kitchen_item_type_uses tu join ref.item_uses u on u.id = tu.use_id
           where tu.type_id = t.id and not tu.is_primary) as other_uses,
         s.label as size_label, ki.capacity_value, m.name as material
  from hh.kitchen_items ki join ref.kitchen_item_types t on t.id = ki.item_type_id
  left join ref.kitchen_item_sizes s on s.id = ki.size_id left join ref.materials m on m.id = ki.material_id
  where ki.deleted_at is null;
create view hh.v_kitchen_inventory_summary with (security_invoker = true) as
  select household_id, kitchen_id, split_part(class_path, ' > ', 1) as class_name, sum(quantity) as items, count(*) as distinct_items
  from hh.v_kitchen_items_classified group by household_id, kitchen_id, split_part(class_path, ' > ', 1);

-- ---- Functions used by the setup questions ----
create function hh.add_kitchen(p_household uuid, p_name text, p_country char(2), p_region text default null,
  p_timezone text default null, p_measurement text default null, p_locale text default null) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into hh.kitchens(household_id, name, is_primary, country_code, region_code, timezone, measurement_system, locale)
  values (p_household, p_name, false, p_country, p_region, p_timezone, p_measurement, p_locale) returning id into v;
  return v;
end $$;

-- Setup screen: master items for a class (e.g. 'glassware'), relevant to this kitchen's country, with how many are already owned
create function hh.setup_checklist(p_kitchen uuid, p_class text)
returns table(type_code text, name text, class_name text, primary_use text, owned int) language sql stable as $$
  select t.code, ref.label('kitchen_item_type', t.id, k.locale, t.name), c.name,
         (select u.name from ref.kitchen_item_type_uses tu join ref.item_uses u on u.id = tu.use_id where tu.type_id = t.id and tu.is_primary),
         coalesce((select sum(ki.quantity)::int from hh.kitchen_items ki
                   where ki.kitchen_id = k.id and ki.item_type_id = t.id and ki.deleted_at is null), 0)
  from hh.kitchens k
  join ref.item_classes root on root.code = p_class
  join ref.kitchen_item_types t on t.class_id in (select ref.class_descendants(root.id)) and t.deleted_at is null
  join ref.item_classes c on c.id = t.class_id
  where k.id = p_kitchen and (t.regions is null or k.country_code = any(t.regions))
  order by t.is_common desc, c.sort_order, t.sort_order, 2 $$;

-- Setup answers -> records. Each element: {type, quantity?, size?, material?, location_id?, brand?, model?, color?,
--   capacity_value?, capacity_unit?, set_pieces?, condition?, nickname?, notes?, id?}  (id makes it safe to retry / sync)
create function hh.setup_items(p_household uuid, p_kitchen uuid, p_items jsonb) returns int
language plpgsql as $$
declare e jsonb; t ref.kitchen_item_types; n int := 0; v_id uuid;
begin
  for e in select * from jsonb_array_elements(p_items) loop
    select * into t from ref.kitchen_item_types where code = e->>'type' and deleted_at is null;
    if not found then raise exception 'unknown_item_type'; end if;
    v_id := coalesce((e->>'id')::uuid, gen_random_uuid());
    insert into hh.kitchen_items(id, household_id, kitchen_id, item_type_id, size_id, quantity, set_pieces, nickname, brand, model,
        material_id, color, capacity_value, capacity_unit_id, location_id, condition, notes)
    values (v_id, p_household, p_kitchen, t.id,
        (select id from ref.kitchen_item_sizes where type_id = t.id and code = e->>'size'),
        coalesce((e->>'quantity')::int, 1), (e->>'set_pieces')::int, e->>'nickname', e->>'brand', e->>'model',
        (select id from ref.materials where code = e->>'material'), e->>'color', (e->>'capacity_value')::numeric,
        (select id from ref.units where code = e->>'capacity_unit'), (e->>'location_id')::uuid,
        coalesce(e->>'condition', 'good'), e->>'notes')
    on conflict (id) do update set size_id = excluded.size_id, quantity = excluded.quantity, set_pieces = excluded.set_pieces,
        nickname = excluded.nickname, brand = excluded.brand, model = excluded.model, material_id = excluded.material_id,
        color = excluded.color, capacity_value = excluded.capacity_value, capacity_unit_id = excluded.capacity_unit_id,
        location_id = excluded.location_id, condition = excluded.condition, notes = excluded.notes, deleted_at = null
      where hh.kitchen_items.household_id = excluded.household_id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Full-detail food entry (regional names accepted: "Ovos", "Eier", "Eggs" resolve to the same master food)
create function hh.add_food(p_household uuid, p_kitchen uuid, p_food_name text, p_qty numeric, p_unit text,
  p_location uuid default null, p_best_by date default null, p_expiration date default null, p_brand text default null,
  p_pack_size numeric default null, p_pack_unit text default null, p_pack_count int default null,
  p_opened_on date default null, p_notes text default null) returns uuid
language plpgsql as $$
declare v_food uuid; v_unit uuid; v_item uuid; v_name text := lower(trim(p_food_name));
begin
  select id into v_unit from ref.units where code = p_unit;
  if v_unit is null then raise exception 'unknown_unit'; end if;
  select f.id into v_food from ref.food_items f
   where f.deleted_at is null and (f.household_id is null or f.household_id = p_household)
     and (lower(f.name) = v_name
       or exists (select 1 from ref.food_item_aliases a where a.food_item_id = f.id and lower(a.alias) = v_name and a.deleted_at is null)
       or exists (select 1 from ref.i18n_labels l where l.entity = 'food_item' and l.entity_id = f.id and l.field = 'name' and lower(l.value) = v_name))
   order by f.household_id nulls last limit 1;
  if v_food is null then
    insert into ref.food_items(household_id, name, default_unit_id) values (p_household, trim(p_food_name), v_unit) returning id into v_food;
  end if;
  insert into hh.inventory_items(household_id, kitchen_id, food_item_id, location_id, display_unit_id, brand, best_by_date,
      expiration_date, pack_size, pack_unit_id, pack_count, opened_on, notes)
  values (p_household, p_kitchen, v_food, p_location, v_unit, p_brand, p_best_by, p_expiration, p_pack_size,
      (select id from ref.units where code = p_pack_unit), p_pack_count, p_opened_on, p_notes) returning id into v_item;
  insert into hh.inventory_transactions(household_id, inventory_item_id, kind, quantity, unit_id) values (p_household, v_item, 'add', p_qty, v_unit);
  return v_item;
end $$;

-- ---- plumbing for the new tables ----
do $$ declare t text; begin
  foreach t in array array['ref.item_classes','ref.item_uses','ref.materials','ref.kitchen_item_types','ref.kitchen_item_sizes',
      'ref.i18n_labels','ref.food_item_packages','hh.kitchen_items','hh.member_kitchens'] loop
    execute format('create trigger trg_touch before insert or update on %s for each row execute function core.touch()', t);
  end loop;
  foreach t in array array['item_classes','item_uses','materials','kitchen_item_types','kitchen_item_type_uses','kitchen_item_sizes','i18n_labels','food_item_packages'] loop
    execute format('alter table ref.%I enable row level security', t);
    execute format('create policy ref_read on ref.%I for select using (true)', t);
  end loop;
  foreach t in array array['kitchen_items','member_kitchens'] loop
    execute format('alter table hh.%I enable row level security', t);
    execute format('create policy tenant_all on hh.%I using (core.is_member(household_id)) with check (core.is_member(household_id))', t);
  end loop;
end $$;
create trigger trg_audit after insert or update or delete on hh.kitchen_items for each row execute function core.audit();
grant select, insert, update, delete on all tables in schema ref, hh to wam_app;
grant select on all tables in schema hh to wam_app;
grant execute on all functions in schema ref, hh to wam_app;
