-- =====================================================================
-- 04_profiling.sql — Question-driven health & food profiles
-- Family members' profiles are NOT predefined: they are built from the
-- profiling questions shown in the app. Questions and options are DATA,
-- so the UI can add/reorder/reword questions without a schema change.
-- Each answer maps (via its option) to one concrete requirement record.
-- =====================================================================
create table ref.profile_questions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  section text not null check (section in ('preferences','allergies','intolerances','diet','health','avoid','prioritize')),
  prompt text not null,                     -- may contain {name} for the member's preferred name
  help_text text,
  input_type text not null check (input_type in ('single','multi','yes_no')),
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table ref.profile_question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references ref.profile_questions(id) on delete cascade,
  code text not null, label text not null, sort_order int not null default 0,
  effect text not null check (effect in ('none','allergy','intolerance','diet','health','like','dislike','avoid','prioritize')),
  allergen_id uuid references ref.allergens(id),
  requirement_type_id uuid references ref.dietary_requirement_types(id),
  health_requirement_type_id uuid references ref.health_requirement_types(id),
  category_id uuid references ref.food_categories(id),
  food_item_id uuid references ref.food_items(id),
  unique (question_id, code), unique (question_id, id),
  check (case effect
    when 'none' then num_nonnulls(allergen_id, requirement_type_id, health_requirement_type_id, category_id, food_item_id) = 0
    when 'allergy' then allergen_id is not null and num_nonnulls(allergen_id, requirement_type_id, health_requirement_type_id, category_id, food_item_id) = 1
    when 'intolerance' then allergen_id is not null and num_nonnulls(allergen_id, requirement_type_id, health_requirement_type_id, category_id, food_item_id) = 1
    when 'diet' then requirement_type_id is not null and num_nonnulls(allergen_id, requirement_type_id, health_requirement_type_id, category_id, food_item_id) = 1
    when 'health' then health_requirement_type_id is not null and num_nonnulls(allergen_id, requirement_type_id, health_requirement_type_id, category_id, food_item_id) = 1
    else num_nonnulls(category_id, food_item_id) = 1 and num_nonnulls(allergen_id, requirement_type_id, health_requirement_type_id) = 0 end),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
create table health.member_profile_answers (   -- what the user ticked, kept as the source of truth
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null, member_id uuid not null,
  question_id uuid not null, option_id uuid not null,
  answered_at timestamptz not null default now(),
  unique (member_id, option_id),
  foreign key (household_id, member_id) references hh.family_members(household_id, id) on delete cascade,
  foreign key (question_id, option_id) references ref.profile_question_options(question_id, id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
-- Derived requirement rows remember which answer produced them; manually entered rows have no source.
alter table health.member_allergies           add column source_option_id uuid references ref.profile_question_options(id);
alter table health.member_intolerances        add column source_option_id uuid references ref.profile_question_options(id);
alter table health.member_dietary_requirements add column source_option_id uuid references ref.profile_question_options(id);
alter table health.member_health_requirements add column source_option_id uuid references ref.profile_question_options(id);
alter table health.member_food_preferences    add column source_option_id uuid references ref.profile_question_options(id);

create function health.apply_profile_answers(p_household uuid, p_member uuid) returns void language plpgsql as $$
declare t text;
begin
  -- 1. retire derived rows whose answer was removed (manual rows are untouched)
  foreach t in array array['member_allergies','member_intolerances','member_dietary_requirements','member_health_requirements','member_food_preferences'] loop
    execute format($f$update health.%I x set deleted_at = now()
      where x.household_id = $1 and x.member_id = $2 and x.source_option_id is not null and x.deleted_at is null
        and not exists (select 1 from health.member_profile_answers a where a.member_id = $2 and a.option_id = x.source_option_id and a.deleted_at is null)$f$, t)
    using p_household, p_member;
  end loop;
  -- 2. create or revive rows for current answers
  insert into health.member_allergies(household_id, member_id, allergen_id, source_option_id)
    select p_household, p_member, o.allergen_id, o.id from health.member_profile_answers a
    join ref.profile_question_options o on o.id = a.option_id
    where a.member_id = p_member and a.deleted_at is null and o.effect = 'allergy'
    on conflict (member_id, allergen_id) do update set deleted_at = null, source_option_id = excluded.source_option_id
      where health.member_allergies.deleted_at is not null;
  insert into health.member_intolerances(household_id, member_id, allergen_id, source_option_id)
    select p_household, p_member, o.allergen_id, o.id from health.member_profile_answers a
    join ref.profile_question_options o on o.id = a.option_id
    where a.member_id = p_member and a.deleted_at is null and o.effect = 'intolerance'
    on conflict (member_id, allergen_id) do update set deleted_at = null, source_option_id = excluded.source_option_id
      where health.member_intolerances.deleted_at is not null;
  insert into health.member_dietary_requirements(household_id, member_id, requirement_type_id, source_option_id)
    select p_household, p_member, o.requirement_type_id, o.id from health.member_profile_answers a
    join ref.profile_question_options o on o.id = a.option_id
    where a.member_id = p_member and a.deleted_at is null and o.effect = 'diet'
    on conflict (member_id, requirement_type_id) do update set deleted_at = null, source_option_id = excluded.source_option_id
      where health.member_dietary_requirements.deleted_at is not null;
  insert into health.member_health_requirements(household_id, member_id, health_requirement_type_id, source_option_id)
    select p_household, p_member, o.health_requirement_type_id, o.id from health.member_profile_answers a
    join ref.profile_question_options o on o.id = a.option_id
    where a.member_id = p_member and a.deleted_at is null and o.effect = 'health'
    on conflict (member_id, health_requirement_type_id) do update set deleted_at = null, source_option_id = excluded.source_option_id
      where health.member_health_requirements.deleted_at is not null;
  insert into health.member_food_preferences(household_id, member_id, kind, category_id, food_item_id, source_option_id)
    select p_household, p_member, o.effect, o.category_id, o.food_item_id, o.id from health.member_profile_answers a
    join ref.profile_question_options o on o.id = a.option_id
    where a.member_id = p_member and a.deleted_at is null and o.effect in ('like','dislike','avoid','prioritize')
      and not exists (select 1 from health.member_food_preferences p
                      where p.member_id = p_member and p.source_option_id = o.id and p.deleted_at is null);
end $$;

-- One call per question screen: replaces the member's answers to that question, then rebuilds derived records.
create function health.save_answers(p_household uuid, p_member uuid, p_question text, p_options text[])
returns void language plpgsql as $$
declare q ref.profile_questions; n int; nn int;
begin
  select * into q from ref.profile_questions where code = p_question and is_active and deleted_at is null;
  if not found then raise exception 'unknown_question'; end if;
  select count(*), count(*) filter (where effect = 'none') into n, nn from ref.profile_question_options
    where question_id = q.id and code = any(p_options) and deleted_at is null;
  if n <> coalesce(array_length(p_options, 1), 0) then raise exception 'unknown_option'; end if;
  if q.input_type in ('single','yes_no') and n > 1 then raise exception 'single_choice_only'; end if;
  if nn > 0 and n > nn then raise exception 'none_is_exclusive'; end if;
  update health.member_profile_answers a set deleted_at = now()
   where a.household_id = p_household and a.member_id = p_member and a.question_id = q.id and a.deleted_at is null
     and a.option_id not in (select id from ref.profile_question_options where question_id = q.id and code = any(p_options));
  insert into health.member_profile_answers(household_id, member_id, question_id, option_id)
    select p_household, p_member, q.id, o.id from ref.profile_question_options o
    where o.question_id = q.id and o.code = any(p_options) and o.deleted_at is null
    on conflict (member_id, option_id) do update set deleted_at = null, answered_at = now()
      where health.member_profile_answers.deleted_at is not null;
  perform health.apply_profile_answers(p_household, p_member);
end $$;

-- Profile completeness (drives "Profile complete / Needs dietary setup" on the member cards)
create view health.v_member_question_status with (security_invoker = true) as
  select m.household_id, m.id as member_id, q.id as question_id, q.code as question_code, q.section,
         exists (select 1 from health.member_profile_answers a
                 where a.member_id = m.id and a.question_id = q.id and a.deleted_at is null) as answered
  from hh.family_members m cross join ref.profile_questions q
  where m.deleted_at is null and q.is_active and q.deleted_at is null;
create view health.v_member_profile_progress with (security_invoker = true) as
  select household_id, member_id, count(*) filter (where answered) as answered_questions, count(*) as total_questions,
         bool_and(answered) as is_complete
  from health.v_member_question_status group by household_id, member_id;

-- ---- plumbing for the new tables (triggers, RLS, grants) ----
create trigger trg_touch before insert or update on ref.profile_questions for each row execute function core.touch();
create trigger trg_touch before insert or update on ref.profile_question_options for each row execute function core.touch();
create trigger trg_touch before insert or update on health.member_profile_answers for each row execute function core.touch();
create trigger trg_audit after insert or update or delete on health.member_profile_answers for each row execute function core.audit();
alter table ref.profile_questions enable row level security;
alter table ref.profile_question_options enable row level security;
create policy ref_read on ref.profile_questions for select using (true);
create policy ref_read on ref.profile_question_options for select using (true);
alter table health.member_profile_answers enable row level security;
create policy health_access on health.member_profile_answers
  using (core.has_role(household_id, array['owner','admin','kitchen_manager','member']))
  with check (core.has_role(household_id, array['owner','admin','kitchen_manager','member']));
grant select, insert, update, delete on ref.profile_questions, ref.profile_question_options, health.member_profile_answers to wam_app;
grant select on health.v_member_question_status, health.v_member_profile_progress to wam_app;
grant execute on all functions in schema health to wam_app;

-- ---- starter question bank (editable data; the app may add or reword any of it) ----
insert into ref.profile_questions(code, section, prompt, help_text, input_type, sort_order) values
 ('likes','preferences','What does {name} enjoy eating?',null,'multi',10),
 ('dislikes','preferences','What does {name} not like?',null,'multi',20),
 ('allergies','allergies','Does {name} have any food allergies?','Allergies mean {name} must avoid these foods.','multi',30),
 ('intolerances','intolerances','Does {name} have any food intolerances?','Foods that upset {name}, but are not allergies.','multi',40),
 ('diet','diet','Does {name} follow any special diet?',null,'multi',50),
 ('health_food','health','Does {name} need any special food requirements?','Optional. Add only what applies.','multi',60),
 ('avoid_foods','avoid','Are there foods {name} should avoid?','Your own choices, separate from allergies.','multi',70),
 ('prioritize_foods','prioritize','Are there foods {name} should eat more of?',null,'multi',80);
insert into ref.profile_question_options(question_id, code, label, sort_order, effect, category_id)
  select pq.id, c.code, c.name, c.sort_order, v.eff, c.id
  from (values ('likes','like'),('dislikes','dislike'),('avoid_foods','avoid'),('prioritize_foods','prioritize')) v(qc, eff)
  join ref.profile_questions pq on pq.code = v.qc
  join ref.food_categories c on not exists (select 1 from ref.food_categories ch where ch.parent_id = c.id);
insert into ref.profile_question_options(question_id, code, label, sort_order, effect, allergen_id)
  select pq.id, a.code, a.name, 10, v.eff, a.id
  from (values ('allergies','allergen','allergy'),('intolerances','intolerance_trigger','intolerance')) v(qc, k, eff)
  join ref.profile_questions pq on pq.code = v.qc join ref.allergens a on a.kind = v.k;
insert into ref.profile_question_options(question_id, code, label, sort_order, effect, requirement_type_id)
  select pq.id, t.code, t.name, 10, 'diet', t.id from ref.profile_questions pq, ref.dietary_requirement_types t where pq.code = 'diet';
insert into ref.profile_question_options(question_id, code, label, sort_order, effect, health_requirement_type_id)
  select pq.id, t.code, t.name, 10, 'health', t.id from ref.profile_questions pq, ref.health_requirement_types t where pq.code = 'health_food';
insert into ref.profile_question_options(question_id, code, label, sort_order, effect)
  select id, 'none', 'None of these', 999, 'none' from ref.profile_questions;
