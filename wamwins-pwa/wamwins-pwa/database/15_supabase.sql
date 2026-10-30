-- =====================================================================
-- 15_supabase.sql — Connect the WAMWins schema to Supabase Auth + the app
-- Run AFTER 01..13 (and before 16_app_catalog.sql). Idempotent where possible.
--   1. core.uid() reads the signed-in Supabase user (auth.uid())
--   2. Supabase's "authenticated" role gets the wam_app privileges
--   3. Every new auth user gets a core.users row (and email verification time)
--   4. The app's schemas are exposed to the REST API
--   5. Small additions the mobile app needs (stable codes, a few columns)
-- =====================================================================

-- 1. identity ----------------------------------------------------------
create or replace function core.uid() returns uuid language sql stable as
$$ select coalesce(auth.uid(), nullif(current_setting('app.user_id', true), '')::uuid) $$;

-- 2. roles -------------------------------------------------------------
grant wam_app to authenticated;
grant usage on schema core, ref, hh, health, capture, match to authenticated, anon;
grant select on all tables in schema ref to anon;                       -- master data is public
grant usage on all sequences in schema core, hh to wam_app;
alter default privileges in schema core, ref, hh, health, capture, match grant select, insert, update, delete on tables to wam_app;
alter default privileges in schema core, ref, hh, health, capture, match grant execute on functions to wam_app;

-- 3. auth.users -> core.users -------------------------------------------
create or replace function core.sync_auth_user() returns trigger language plpgsql security definer
set search_path = core, public, pg_temp as $$
declare md jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
        full_name text := coalesce(md->>'full_name', md->>'name');
begin
  insert into core.users(id, email, first_name, last_name, email_verified_at)
  values (new.id, new.email,
          coalesce(md->>'first_name', split_part(full_name, ' ', 1)),
          coalesce(md->>'last_name', nullif(substr(full_name, length(split_part(full_name, ' ', 1)) + 2), '')),
          new.email_confirmed_at)
  on conflict (id) do update set email = excluded.email,
     first_name = coalesce(core.users.first_name, excluded.first_name),
     last_name = coalesce(core.users.last_name, excluded.last_name),
     email_verified_at = coalesce(excluded.email_verified_at, core.users.email_verified_at);
  return new;
end $$;
drop trigger if exists trg_wam_user on auth.users;
create trigger trg_wam_user after insert or update of email, email_confirmed_at, raw_user_meta_data on auth.users
  for each row execute function core.sync_auth_user();
insert into core.users(id, email, first_name, last_name, email_verified_at)          -- backfill existing accounts
  select u.id, u.email, u.raw_user_meta_data->>'first_name', u.raw_user_meta_data->>'last_name', u.email_confirmed_at
  from auth.users u where u.email is not null
  on conflict (id) do nothing;

-- 4. expose schemas to the REST API (also add them in Dashboard > Settings > API > Exposed schemas)
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, core, ref, hh, health, match';
notify pgrst, 'reload config';

-- 5. app additions -------------------------------------------------------
-- stable codes so the app and the database agree on master data
alter table ref.food_items add column if not exists code text;
create unique index if not exists uq_food_item_code on ref.food_items(code) where code is not null;
alter table ref.recipes add column if not exists code text;
create unique index if not exists uq_recipe_code on ref.recipes(code) where code is not null;

-- members: exact age and the "other relative" relationship used by the app
alter table hh.family_members add column if not exists age_years smallint check (age_years between 0 and 130);
alter table hh.family_members drop constraint if exists family_members_relationship_check;
alter table hh.family_members add constraint family_members_relationship_check check (relationship in
  ('self','spouse_partner','parent','child','sibling','grandparent','caregiver','relative','other'));

-- inventory lot: amount first added (default low-stock level) and a custom alert level, package label
alter table hh.inventory_items add column if not exists initial_qty numeric(14,4),
  add column if not exists low_alert numeric(14,4), add column if not exists pack_label text;

-- shopping list items belong to a kitchen and can carry a short note ("For Peanut Noodles")
alter table hh.shopping_list_items add column if not exists kitchen_id uuid, add column if not exists note text;
-- meal history: which kitchen, and what was taken from stock
alter table hh.meal_logs add column if not exists kitchen_id uuid, add column if not exists used jsonb;

-- household-custom foods may carry allergens (needed for allergy checks on custom items)
drop policy if exists hh_write on ref.food_item_allergens;
create policy hh_write on ref.food_item_allergens for all
  using (exists (select 1 from ref.food_items f where f.id = food_item_id and f.household_id is not null and core.is_member(f.household_id)))
  with check (exists (select 1 from ref.food_items f where f.id = food_item_id and f.household_id is not null and core.is_member(f.household_id)));

-- consent documents the app records against
insert into core.consent_documents(kind, version, locale) values ('terms','1.0','en-US'),('privacy','1.0','en-US'),('health_data','1.0','en-US')
  on conflict (kind, version, locale) do nothing;

-- owner can delete the whole household ("Delete my household" in the app)
create or replace function core.delete_household(p_household uuid) returns void language plpgsql security definer
set search_path = core, pg_temp as $$
begin
  if not core.has_role(p_household, array['owner']) then raise exception 'forbidden'; end if;
  insert into core.data_requests(user_id, household_id, kind, status, completed_at) values (core.uid(), p_household, 'delete', 'completed', now());
  delete from core.households where id = p_household;
end $$;
grant execute on function core.delete_household(uuid) to wam_app;
