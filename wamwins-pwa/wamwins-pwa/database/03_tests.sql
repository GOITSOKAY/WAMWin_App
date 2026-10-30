-- Behavioural tests. Run after 01 + 02. Raises on failure.
\set ON_ERROR_STOP on
begin;
insert into core.users(id,email,first_name,last_name) values
 ('11111111-1111-1111-1111-111111111111','maria@example.com','Maria','Smith'),
 ('22222222-2222-2222-2222-222222222222','other@example.com','Sam','Lee');
insert into core.users(id,email,first_name) values ('33333333-3333-3333-3333-333333333333','spouse@example.com','John');

-- Recipes (system) used by the matching test
insert into ref.recipes(id,title,is_system) values
 ('aaaaaaaa-0000-0000-0000-000000000001','Tomato Pasta Bake',true),
 ('aaaaaaaa-0000-0000-0000-000000000002','Peanut Noodles',true),
 ('aaaaaaaa-0000-0000-0000-000000000003','Salmon Bowl',true);
insert into ref.recipe_ingredients(recipe_id,food_item_id,quantity,unit_id)
 select r.id, f.id, v.q, u.id from (values
  ('Tomato Pasta Bake','Pasta',8,'oz'),('Tomato Pasta Bake','Tomatoes',3,'each'),('Tomato Pasta Bake','Cheddar cheese',4,'oz'),
  ('Peanut Noodles','Pasta',8,'oz'),('Peanut Noodles','Peanut butter',4,'oz'),
  ('Salmon Bowl','Salmon',1,'lb'),('Salmon Bowl','Rice',1,'cup')) v(r,i,q,u)
 join ref.recipes r on r.title = v.r join ref.food_items f on f.name = v.i and f.household_id is null join ref.units u on u.code = v.u;
insert into ref.recipe_appliance_requirements select 'aaaaaaaa-0000-0000-0000-000000000001', id, true from ref.appliance_types where code='oven';
insert into ref.recipe_nutrients select 'aaaaaaaa-0000-0000-0000-000000000001', id, 900 from ref.nutrients where code='sodium';

set local role wam_app;
set local app.user_id = '11111111-1111-1111-1111-111111111111';
do $$
declare hh uuid; pantry uuid; leo uuid; r record; n int; ok boolean;
begin
  hh := core.create_household('11111111-1111-1111-1111-111111111111','The Smith Family','US','FL','America/New_York',5);

  -- FREE TIER: second user seat must be refused
  begin
    insert into core.household_memberships(household_id,user_id,role) values (hh,'33333333-3333-3333-3333-333333333333','member');
    raise exception 'TEST FAILED: seat limit not enforced';
  exception when others then
    if sqlerrm <> 'seat_limit_reached' then raise; end if;
  end;
  -- ...but unlimited family member PROFILES are fine
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Leo','child') returning id into leo;
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'John','spouse_partner');

  -- Dynamic kitchen setup: pantry with 4 shelves
  pantry := hh.setup_storage(hh,'pantry',null,4);
  perform hh.setup_storage(hh,'refrigerator'); perform hh.setup_storage(hh,'freezer');
  select count(*) into n from hh.locations where household_id=hh; assert n = 7, 'expected pantry+4 shelves+fridge+freezer, got '||n;
  assert hh.setup_appliances(hh, array['oven','range','refrigerator']) = 3;
  assert hh.setup_appliances(hh, array['oven']) = 0, 'appliance setup must be idempotent';

  -- Leo: peanut allergy (hard block), lactose intolerance (warning)
  insert into health.member_allergies(household_id,member_id,allergen_id) select hh, leo, id from ref.allergens where code='peanuts';
  insert into health.member_intolerances(household_id,member_id,allergen_id) select hh, leo, id from ref.allergens where code='lactose';

  -- Manual inventory
  perform hh.add_inventory(hh,'Pasta',2,'lb',pantry);
  perform hh.add_inventory(hh,'Tomatoes',6,'each',null);
  perform hh.add_inventory(hh,'Cheddar cheese',8,'oz',null);
  perform hh.add_inventory(hh,'Peanut butter',16,'oz',pantry);
  perform hh.add_inventory(hh,'Quinoa',1,'lb',pantry);   -- custom food item created on the fly

  select * into r from match.match_recipes(hh, null) where title = 'Peanut Noodles';
  assert r.blocked and r.fit_score = 0, 'peanut recipe must be blocked for Leo';
  select * into r from match.match_recipes(hh, null) where title = 'Tomato Pasta Bake';
  assert not r.blocked and r.availability_pct = 100, 'pasta bake should be available';
  assert r.reasons @> '[{"type":"intolerance","member":"Leo"}]', 'lactose warning missing';
  select * into r from match.match_recipes(hh, null) where title = 'Salmon Bowl';
  assert r.availability_pct = 0, 'no salmon or rice in stock';
  -- members not involved in the meal are not considered
  select * into r from match.match_recipes(hh, array[(select id from hh.family_members where household_id=hh and preferred_name='John')]) where title='Peanut Noodles';
  assert not r.blocked, 'John eating alone: peanut recipe allowed';

  -- Ledger: using stock lowers quantity; emptying marks consumed; overdraw is rejected
  declare it uuid; q numeric; st text; n2 int; begin
    select id into it from hh.inventory_items where household_id=hh and food_item_id=(select id from ref.food_items where name='Cheddar cheese' and household_id is null);
    insert into hh.inventory_transactions(household_id,inventory_item_id,kind,quantity,unit_id) select hh,it,'use',4,id from ref.units where code='oz';
    select qty_base,status into q,st from hh.inventory_items where id=it; assert round(q,1) = 113.4 and st='active', 'use should leave 4 oz, got '||q;
    insert into hh.inventory_transactions(household_id,inventory_item_id,kind,quantity,unit_id) select hh,it,'consume',4,id from ref.units where code='oz';
    select status into st from hh.inventory_items where id=it; assert st='consumed';
    begin
      insert into hh.inventory_transactions(household_id,inventory_item_id,kind,quantity,unit_id) select hh,it,'use',1,id from ref.units where code='oz';
      raise exception 'TEST FAILED: overdraw allowed';
    exception when check_violation then null; end;
    update hh.inventory_transactions set note='x' where inventory_item_id=it;
    get diagnostics n = row_count; assert n = 0, 'ledger rows must not be updatable by the app role';
  end;

  -- Higher-tier capability gating: capture is blocked on Free
  begin
    insert into capture.capture_sessions(household_id,kind) values (hh,'barcode');
    raise exception 'TEST FAILED: capture allowed on Free tier';
  exception when others then if sqlerrm <> 'capability_required' then raise; end if; end;

  -- Setup progress and sync cursor
  assert (select count(*) from core.setup_progress where household_id=hh and status='done') = 1;
  assert (select count(*) from hh.inventory_items where household_id=hh and rev > 0) >= 5;

  -- Tenant isolation: another user sees nothing
  perform set_config('app.user_id','22222222-2222-2222-2222-222222222222',true);
  assert (select count(*) from hh.inventory_items) = 0, 'RLS leak: inventory';
  assert (select count(*) from health.member_allergies) = 0, 'RLS leak: health';
  assert (select count(*) from hh.family_members) = 0, 'RLS leak: family';
  raise notice 'ALL TESTS PASSED';
end $$;
rollback;
