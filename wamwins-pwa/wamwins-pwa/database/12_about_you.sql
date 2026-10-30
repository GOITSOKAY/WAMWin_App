-- =====================================================================
-- 12_about_you.sql — "About You" answers and setup-step control
--   household role (Parent, Homemaker, ...) and what the user wants help with
--   are stored, not just shown; setup steps can be completed or skipped.
-- =====================================================================
alter table core.household_memberships add column household_role text
  check (household_role in ('parent','homemaker','spouse_partner','household_manager','kitchen_manager','caregiver','family_member','other'));
create table ref.help_goals (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, name text not null, sort_order int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
insert into ref.help_goals(code, name, sort_order) values
 ('decide_what_to_cook','Decide what to cook',1),('manage_inventory','Manage food inventory',2),('eat_healthier','Eat healthier',3),
 ('support_family_requirements','Support family food requirements',4),('reduce_food_waste','Reduce food waste',5),
 ('organize_kitchen','Organize the kitchen',6),('reduce_grocery_spend','Reduce unnecessary grocery purchases',7);
create table core.membership_goals (
  household_id uuid not null, user_id uuid not null, goal_id uuid not null references ref.help_goals(id),
  primary key (household_id, user_id, goal_id),
  foreign key (household_id, user_id) references core.household_memberships(household_id, user_id) on delete cascade,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
do $$ declare t text; begin
  foreach t in array array['ref.help_goals','core.membership_goals'] loop
    execute format('create trigger trg_touch before insert or update on %s for each row execute function core.touch()', t);
  end loop;
end $$;
alter table ref.help_goals enable row level security;
create policy ref_read on ref.help_goals for select using (true);
alter table core.membership_goals enable row level security;
create policy goals_self on core.membership_goals using (user_id = core.uid() and core.is_member(household_id))
  with check (user_id = core.uid() and core.is_member(household_id));

create function core.set_setup_step(p_household uuid, p_step text, p_status text) returns void language plpgsql as $$
begin
  if p_status not in ('pending','in_progress','done','skipped') then raise exception 'invalid_status'; end if;
  insert into core.setup_progress(household_id, step_code, status, completed_at)
    values (p_household, p_step, p_status, case when p_status in ('done','skipped') then now() end)
  on conflict (household_id, step_code) do update set status = excluded.status, completed_at = excluded.completed_at, deleted_at = null;
end $$;

create function core.save_about_you(p_household uuid, p_display_name text, p_role text, p_goals text[]) returns void
language plpgsql security definer set search_path = core, hh, ref, pg_temp as $$
declare v_uid uuid := core.uid(); n int; g int;
begin
  if v_uid is null or not exists (select 1 from core.household_memberships where household_id = p_household and user_id = v_uid
      and status = 'active' and deleted_at is null) then raise exception 'not_a_member'; end if;
  if length(trim(coalesce(p_display_name, ''))) = 0 then raise exception 'name_required'; end if;
  select count(*) into g from ref.help_goals where code = any(coalesce(p_goals, '{}')) and deleted_at is null;
  if g <> coalesce(array_length(p_goals, 1), 0) then raise exception 'unknown_goal'; end if;
  update core.household_memberships set household_role = p_role where household_id = p_household and user_id = v_uid and deleted_at is null;
  update hh.family_members set preferred_name = trim(p_display_name) where household_id = p_household and user_id = v_uid and deleted_at is null;
  delete from core.membership_goals where household_id = p_household and user_id = v_uid;
  insert into core.membership_goals(household_id, user_id, goal_id)
    select p_household, v_uid, id from ref.help_goals where code = any(coalesce(p_goals, '{}')) and deleted_at is null;
  perform core.set_setup_step(p_household, 'about_you', 'done');
end $$;
grant select, insert, update, delete on ref.help_goals, core.membership_goals to wam_app;
grant execute on function core.set_setup_step(uuid, text, text), core.save_about_you(uuid, text, text, text[]) to wam_app;
