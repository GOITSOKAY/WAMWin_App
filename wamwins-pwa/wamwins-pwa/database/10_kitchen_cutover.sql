-- 10: move appliances/utensils into the unified kitchen_items detail file, make matching kitchen-aware
insert into hh.kitchen_items(id, household_id, kitchen_id, item_type_id, nickname, location_id, quantity, status, created_at, updated_at, deleted_at)
 select ha.id, ha.household_id, (select id from hh.kitchens k where k.household_id = ha.household_id and k.is_primary and k.deleted_at is null limit 1),
        t.id, ha.nickname, ha.location_id, ha.quantity, ha.status, ha.created_at, ha.updated_at, ha.deleted_at
 from hh.household_appliances ha join ref.appliance_types at on at.id = ha.appliance_type_id
 join ref.kitchen_item_types t on t.code = case at.code when 'other' then 'other_appliance' else at.code end;
insert into hh.kitchen_items(id, household_id, kitchen_id, item_type_id, nickname, location_id, quantity, created_at, updated_at, deleted_at)
 select hu.id, hu.household_id, (select id from hh.kitchens k where k.household_id = hu.household_id and k.is_primary and k.deleted_at is null limit 1),
        t.id, hu.nickname, hu.location_id, coalesce(hu.quantity, 1), hu.created_at, hu.updated_at, hu.deleted_at
 from hh.household_utensils hu join ref.utensil_types ut on ut.id = hu.utensil_type_id
 join ref.kitchen_item_types t on t.code = case ut.code when 'other' then 'other_tool' else ut.code end;
drop table hh.household_appliances;
drop table hh.household_utensils;
update hh.inventory_items i set kitchen_id = coalesce((select kitchen_id from hh.locations l where l.household_id = i.household_id and l.id = i.location_id),
   (select id from hh.kitchens k where k.household_id = i.household_id and k.is_primary and k.deleted_at is null limit 1)) where kitchen_id is null;
-- compatibility view: recipes still require appliance TYPES
create view hh.household_appliances with (security_invoker = true) as
  select ki.id, ki.household_id, ki.kitchen_id, t.appliance_type_id, ki.nickname, ki.location_id, ki.quantity, ki.status, ki.deleted_at
  from hh.kitchen_items ki join ref.kitchen_item_types t on t.id = ki.item_type_id where t.appliance_type_id is not null;
grant select on hh.household_appliances to wam_app;

create or replace function hh.setup_appliances(p_household uuid, p_codes text[]) returns int
language plpgsql set search_path = hh, ref, pg_temp as $$
declare n int; k uuid;
begin
  select id into k from hh.kitchens where household_id = p_household and is_primary and deleted_at is null limit 1;
  insert into hh.kitchen_items(household_id, kitchen_id, item_type_id)
    select p_household, k, t.id from ref.kitchen_item_types t
    where t.code = any(p_codes) and t.appliance_type_id is not null and t.deleted_at is null
      and not exists (select 1 from hh.kitchen_items ki where ki.household_id = p_household and ki.kitchen_id = k
                      and ki.item_type_id = t.id and ki.deleted_at is null);
  get diagnostics n = row_count; return n;
end $$;
create or replace function hh.setup_utensils(p_household uuid, p_codes text[]) returns int
language plpgsql set search_path = hh, ref, pg_temp as $$
declare n int; k uuid;
begin
  select id into k from hh.kitchens where household_id = p_household and is_primary and deleted_at is null limit 1;
  insert into hh.kitchen_items(household_id, kitchen_id, item_type_id)
    select p_household, k, t.id from ref.kitchen_item_types t
    where t.code = any(p_codes) and t.appliance_type_id is null and t.deleted_at is null
      and not exists (select 1 from hh.kitchen_items ki where ki.household_id = p_household and ki.kitchen_id = k
                      and ki.item_type_id = t.id and ki.deleted_at is null);
  get diagnostics n = row_count; return n;
end $$;

-- matching: optional kitchen scope (null = all of the household's kitchens)
drop function match.match_recipes(uuid, uuid[]);
create function match.match_recipes(p_household uuid, p_members uuid[] default null, p_kitchen uuid default null)
returns table (recipe_id uuid, title text, fit_score int, availability_pct int, blocked boolean, reasons jsonb)
language sql stable as $$
with
mem as (select m.id, m.preferred_name as nm from hh.family_members m
        where m.household_id = p_household and m.deleted_at is null and (p_members is null or m.id = any(p_members))),
cand as (select r.id, r.title from ref.recipes r
         where r.deleted_at is null and r.is_published and (r.household_id is null or r.household_id = p_household)),
stock as (select i.food_item_id, sum(i.qty_base) as q from hh.inventory_items i
          where i.household_id = p_household and i.deleted_at is null and i.status = 'active'
            and (p_kitchen is null or i.kitchen_id = p_kitchen)
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
      where ha.household_id = p_household and (p_kitchen is null or ha.kitchen_id = p_kitchen)
        and ha.appliance_type_id = ra.appliance_type_id and ha.status = 'active' and ha.deleted_at is null)
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
grant execute on all functions in schema match, hh to wam_app;
