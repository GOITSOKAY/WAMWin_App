-- Scenario: a 5-person family (two parents, three children) with kitchens in North America, South America and Europe.
\set ON_ERROR_STOP on
begin;
insert into core.users(id,email,first_name) values ('11111111-1111-1111-1111-111111111111','maria@example.com','Maria'),
  ('22222222-2222-2222-2222-222222222222','other@example.com','Sam');
insert into ref.recipes(id,title,is_system) values ('bbbbbbbb-0000-0000-0000-000000000001','Oven Baked Eggs',true);
insert into ref.recipe_ingredients(recipe_id,food_item_id,quantity,unit_id)
  select 'bbbbbbbb-0000-0000-0000-000000000001', f.id, 6, u.id from ref.food_items f, ref.units u where f.name='Eggs' and f.household_id is null and u.code='each';
insert into ref.recipe_appliance_requirements select 'bbbbbbbb-0000-0000-0000-000000000001', id, true from ref.appliance_types where code='oven';

set local role wam_app;
set local app.user_id = '11111111-1111-1111-1111-111111111111';
do $$
declare hh uuid; us uuid; br uuid; de uuid; ana uuid; lukas uuid; n int; r record; eggs uuid; item uuid; loc uuid; it uuid;
begin
  hh := core.create_household('11111111-1111-1111-1111-111111111111','The Silva Family','US','FL','America/New_York',5);
  select id into us from hh.kitchens where household_id = hh and is_primary;
  assert (select measurement_system from hh.kitchens where id = us) = 'us', 'primary kitchen inherits household settings';
  br := hh.add_kitchen(hh,'Apartamento São Paulo','BR','SP','America/Sao_Paulo','metric','pt-BR');
  de := hh.add_kitchen(hh,'Wohnung München','DE','BY','Europe/Berlin','metric','de-DE');
  begin update hh.kitchens set is_primary = true where id = br; raise exception 'TEST FAILED: two primary kitchens';
  exception when unique_violation then null; end;

  -- five family members, each with a home kitchen
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Carlos','spouse_partner');
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Sofia','child');
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Ana','child') returning id into ana;
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Lukas','child') returning id into lukas;
  assert (select count(*) from hh.family_members where household_id = hh) = 5;
  insert into hh.member_kitchens(household_id,member_id,kitchen_id,is_home)
    select hh, m.id, us, true from hh.family_members m where m.household_id = hh and m.preferred_name in ('Carlos','Sofia') or m.is_account_holder and m.household_id = hh;
  insert into hh.member_kitchens(household_id,member_id,kitchen_id,is_home) values (hh,ana,br,true),(hh,lukas,de,true);
  begin insert into hh.member_kitchens(household_id,member_id,kitchen_id,is_home) values (hh,ana,us,true); raise exception 'TEST FAILED: two homes';
  exception when unique_violation then null; end;

  -- regional checklists: what is asked depends on the kitchen's country, labels follow its language
  assert exists (select 1 from hh.setup_checklist(de,'small_appliances') where type_code = 'raclette_grill'), 'raclette asked in Germany';
  assert not exists (select 1 from hh.setup_checklist(us,'small_appliances') where type_code = 'raclette_grill'), 'not asked in US';
  assert exists (select 1 from hh.setup_checklist(br,'cups_mugs') where type_code = 'mate_gourd'), 'mate gourd asked in Brazil';
  assert not exists (select 1 from hh.setup_checklist(de,'cups_mugs') where type_code = 'mate_gourd');
  assert (select name from hh.setup_checklist(br,'cookware') where type_code = 'frying_pan') = 'Frigideira';
  assert (select name from hh.setup_checklist(de,'cookware') where type_code = 'frying_pan') = 'Bratpfanne';
  assert (select name from hh.setup_checklist(us,'cookware') where type_code = 'frying_pan') = 'Frying Pan';
  assert (select count(*) from hh.setup_checklist(us,'glassware')) >= 20, 'glassware master list is complete';

  -- answers -> detail records (glassware, cookware, dining wares)
  n := hh.setup_items(hh, us, '[{"type":"red_wine_glass","quantity":6,"size":"std","material":"crystal","brand":"Riedel"},
    {"type":"white_wine_glass","quantity":6,"size":"std"},{"type":"champagne_flute","quantity":4},
    {"type":"water_tumbler","quantity":10,"size":"large","material":"glass"},{"type":"pint_glass","quantity":4,"size":"us"},
    {"type":"shot_glass","quantity":6},{"type":"wine_decanter","quantity":1,"size":"std"},
    {"type":"frying_pan","quantity":2,"size":"10in","material":"nonstick"},{"type":"dinner_plate","quantity":12,"set_pieces":12}]');
  assert n = 9;
  select * into r from hh.v_kitchen_items_classified where kitchen_id = us and type_code = 'red_wine_glass';
  assert r.class_path = 'Glassware > Wine Glasses' and r.primary_use = 'Wine' and r.size_label = 'Standard 12 oz' and r.material = 'Crystal', 'classified by type, use, size, material';
  select * into r from hh.v_kitchen_items_classified where kitchen_id = us and type_code = 'wine_decanter';
  assert r.primary_use = 'Serving' and r.other_uses = 'Wine', 'multi-purpose items carry secondary uses';
  assert (select primary_use from hh.v_kitchen_items_classified where kitchen_id = us and type_code = 'champagne_flute') = 'Sparkling wine';
  assert (select items from hh.v_kitchen_inventory_summary where kitchen_id = us and class_name = 'Glassware') = 37, 'glassware total';
  assert (select owned from hh.setup_checklist(us,'glassware') where type_code = 'red_wine_glass') = 6, 'checklist shows owned count';
  -- retry-safe (client id)
  perform hh.setup_items(hh, us, '[{"id":"cccccccc-0000-0000-0000-000000000001","type":"mug","quantity":4}]');
  perform hh.setup_items(hh, us, '[{"id":"cccccccc-0000-0000-0000-000000000001","type":"mug","quantity":6}]');
  assert (select count(*) from hh.kitchen_items where id = 'cccccccc-0000-0000-0000-000000000001') = 1
     and (select quantity from hh.kitchen_items where id = 'cccccccc-0000-0000-0000-000000000001') = 6, 'upsert by client id';
  begin perform hh.setup_items(hh, us, '[{"type":"not_a_real_item"}]'); raise exception 'TEST FAILED: unknown item';
  exception when others then if sqlerrm <> 'unknown_item_type' then raise; end if; end;
  begin insert into hh.kitchen_items(household_id,item_type_id,quantity) select hh, id, 0 from ref.kitchen_item_types limit 1; raise exception 'TEST FAILED: zero quantity';
  exception when check_violation then null; end;

  -- foods in the Brazilian kitchen, entered with a Portuguese name and package details
  select id into eggs from ref.food_items where name = 'Eggs' and household_id is null;
  item := hh.add_food(hh, br, 'Ovos', 12, 'each', null, null, current_date + 20, 'Granja', 12, 'each', 1, null, 'dúzia');
  assert (select food_item_id from hh.inventory_items where id = item) = eggs, 'regional name resolves to the master food';
  assert (select kitchen_id from hh.inventory_items where id = item) = br;
  assert (select pack_size from hh.inventory_items where id = item) = 12;
  loc := hh.setup_storage(hh, 'refrigerator');                -- belongs to the primary (US) kitchen
  begin perform hh.add_food(hh, br, 'Rice', 1, 'kg', loc); raise exception 'TEST FAILED: location from another kitchen';
  exception when others then if sqlerrm <> 'location_kitchen_mismatch' then raise; end if; end;

  -- matching is kitchen-aware: stock and appliances come from the kitchen being cooked in
  perform hh.setup_items(hh, us, '[{"type":"oven"}]');
  select * into r from match.match_recipes(hh, null, br) where title = 'Oven Baked Eggs';
  assert r.blocked and r.reasons @> '[{"type":"appliance"}]', 'Brazil kitchen has eggs but no oven';
  select * into r from match.match_recipes(hh, null, us) where title = 'Oven Baked Eggs';
  assert not r.blocked and r.availability_pct = 0, 'US kitchen has an oven but no eggs';
  perform hh.setup_items(hh, br, '[{"type":"oven"}]');
  select * into r from match.match_recipes(hh, null, br) where title = 'Oven Baked Eggs';
  assert not r.blocked and r.availability_pct = 100 and r.fit_score = 100, 'Brazil kitchen can now cook it';
  assert (select availability_pct from match.match_recipes(hh) where title = 'Oven Baked Eggs') = 100, 'all-kitchens view';

  -- master data quality + localisation
  assert not exists (select 1 from ref.kitchen_item_types t where not exists
    (select 1 from ref.kitchen_item_type_uses u where u.type_id = t.id and u.is_primary)), 'every master item has a primary use';
  assert ref.label('food_item', eggs, 'pt-BR', 'x') = 'Ovos' and ref.label('food_item', eggs, 'es-AR', 'x') = 'Huevos'
     and ref.label('food_item', eggs, 'it', 'Eggs') = 'Eggs', 'label fallback chain';
  assert exists (select 1 from ref.food_item_packages p join ref.food_items f on f.id = p.food_item_id
     where f.name = 'Pasta' and p.country_code = 'DE' and p.label = '500 g pack'), 'regional pack sizes';

  -- isolation: another account sees none of this household
  perform set_config('app.user_id','22222222-2222-2222-2222-222222222222',true);
  assert (select count(*) from hh.kitchen_items) = 0 and (select count(*) from hh.kitchens) = 0
     and (select count(*) from hh.member_kitchens) = 0 and (select count(*) from hh.inventory_items) = 0, 'RLS leak';
  raise notice 'KITCHEN TESTS PASSED';
end $$;
rollback;
