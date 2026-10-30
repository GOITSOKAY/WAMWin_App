-- =====================================================================
-- 06_age_rules.sql — Age-dependent profiling questions
-- Each question may declare an age window. A member sees it only if their
-- age (from birth date, or else the age range chosen in the app) falls in
-- that window. Questions with no window apply to everyone. If a member's
-- age is unknown, only questions with no window are shown.
-- =====================================================================
create table ref.age_bands (
  code text primary key, label text not null,
  min_years numeric not null, max_years numeric not null,       -- [min, max)
  sort_order int not null default 0, check (min_years < max_years),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz, rev bigint not null default nextval('core.rev_seq')
);
insert into ref.age_bands(code,label,min_years,max_years,sort_order) values
 ('under_1','Under 1',0,1,1),('age_1_2','1–2',1,3,2),('age_3_5','3–5',3,6,3),('age_6_12','6–12',6,13,4),
 ('age_13_17','13–17',13,18,5),('age_18_64','18–64',18,65,6),('age_65_plus','65 and over',65,150,7);
alter table ref.age_bands enable row level security;
create policy ref_read on ref.age_bands for select using (true);
create trigger trg_touch before insert or update on ref.age_bands for each row execute function core.touch();
grant select, insert, update, delete on ref.age_bands to wam_app;
alter table hh.family_members add constraint fk_member_age_range foreign key (age_range) references ref.age_bands(code);

alter table ref.profile_questions add column min_age_years numeric check (min_age_years >= 0);   -- inclusive
alter table ref.profile_questions add column max_age_years numeric check (max_age_years > 0);    -- exclusive
alter table ref.profile_questions add constraint chk_age_window check (min_age_years is null or max_age_years is null or min_age_years < max_age_years);

create function hh.member_age_span(p_member uuid) returns table(lo numeric, hi numeric) language sql stable as $$
  select case when m.birth_date is not null then (current_date - m.birth_date) / 365.25 else b.min_years end,
         case when m.birth_date is not null then (current_date - m.birth_date) / 365.25 + 0.0001 else b.max_years end
  from hh.family_members m left join ref.age_bands b on b.code = m.age_range where m.id = p_member $$;

create function health.question_applies(p_member uuid, p_min numeric, p_max numeric) returns boolean
language sql stable as $$
  select case when p_min is null and p_max is null then true
    else coalesce((select s.lo is not null and (p_max is null or s.lo < p_max) and (p_min is null or s.hi > p_min)
                   from hh.member_age_span(p_member) s), false) end $$;

-- completeness now counts only the questions that apply to the member
create or replace view health.v_member_question_status with (security_invoker = true) as
  select m.household_id, m.id as member_id, q.id as question_id, q.code as question_code, q.section,
         exists (select 1 from health.member_profile_answers a
                 where a.member_id = m.id and a.question_id = q.id and a.deleted_at is null) as answered
  from hh.family_members m cross join ref.profile_questions q
  where m.deleted_at is null and q.is_active and q.deleted_at is null
    and health.question_applies(m.id, q.min_age_years, q.max_age_years);

-- What the app asks next: only applicable questions, prompt already personalised
create function health.questions_for_member(p_member uuid)
returns table(code text, section text, prompt text, help_text text, input_type text, sort_order int, answered boolean)
language sql stable as $$
  select q.code, q.section, replace(q.prompt, '{name}', m.preferred_name), replace(q.help_text, '{name}', m.preferred_name),
         q.input_type, q.sort_order,
         exists (select 1 from health.member_profile_answers a where a.member_id = m.id and a.question_id = q.id and a.deleted_at is null)
  from hh.family_members m join ref.profile_questions q
    on q.is_active and q.deleted_at is null and health.question_applies(m.id, q.min_age_years, q.max_age_years)
  where m.id = p_member and m.deleted_at is null order by q.sort_order $$;

create or replace function health.save_answers(p_household uuid, p_member uuid, p_question text, p_options text[])
returns void language plpgsql as $$
declare q ref.profile_questions; n int; nn int;
begin
  select * into q from ref.profile_questions where code = p_question and is_active and deleted_at is null;
  if not found then raise exception 'unknown_question'; end if;
  if not health.question_applies(p_member, q.min_age_years, q.max_age_years) then raise exception 'question_not_applicable'; end if;
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
grant execute on all functions in schema health, hh to wam_app;

-- Example age-gated question: caregivers of very young children choose foods not yet introduced.
-- Age windows on any other question are editable data; set them with your nutrition adviser.
insert into ref.profile_questions(code, section, prompt, help_text, input_type, sort_order, min_age_years, max_age_years) values
 ('not_yet_introduced','avoid','Are there foods you are not giving {name} yet?','Your choice as a caregiver. Add what you are waiting on.','multi',75,0,3);
insert into ref.profile_question_options(question_id, code, label, sort_order, effect, category_id)
  select pq.id, c.code, c.name, c.sort_order, 'avoid', c.id from ref.profile_questions pq
  join ref.food_categories c on c.code in ('meat','poultry','seafood','legumes','eggs','dairy','spices')
  where pq.code = 'not_yet_introduced';
insert into ref.profile_question_options(question_id, code, label, sort_order, effect)
  select id, 'none', 'None of these', 999, 'none' from ref.profile_questions where code = 'not_yet_introduced';
