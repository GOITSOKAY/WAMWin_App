\set ON_ERROR_STOP on
begin;
insert into core.users(id,email,first_name) values ('11111111-1111-1111-1111-111111111111','maria@example.com','Maria');
set local role wam_app;
set local app.user_id = '11111111-1111-1111-1111-111111111111';
do $$
declare hh uuid; baby uuid; kid uuid; teen uuid; unk uuid; edge uuid; r record;
begin
  hh := core.create_household('11111111-1111-1111-1111-111111111111','The Smith Family');
  insert into hh.family_members(household_id,preferred_name,relationship,birth_date) values (hh,'Bea','child',current_date - 240) returning id into baby;       -- ~8 months
  insert into hh.family_members(household_id,preferred_name,relationship,age_range) values (hh,'Leo','child','age_6_12') returning id into kid;
  insert into hh.family_members(household_id,preferred_name,relationship,age_range) values (hh,'Toddler','child','age_1_2') returning id into teen;
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Unknown','other') returning id into unk;
  insert into hh.family_members(household_id,preferred_name,relationship,birth_date) values (hh,'Edge','child', (current_date - interval '3 years')::date) returning id into edge;

  assert exists (select 1 from health.questions_for_member(baby) where code = 'not_yet_introduced'), 'infant sees the age-gated question';
  assert exists (select 1 from health.questions_for_member(teen) where code = 'not_yet_introduced'), 'age band 1-2 overlaps the 0-3 window';
  assert not exists (select 1 from health.questions_for_member(kid) where code = 'not_yet_introduced'), '6-12 must not see it';
  assert not exists (select 1 from health.questions_for_member(unk) where code = 'not_yet_introduced'), 'unknown age sees only ungated questions';
  assert not exists (select 1 from health.questions_for_member(edge) where code = 'not_yet_introduced'), 'window upper bound (3 years) is exclusive';
  assert (select prompt from health.questions_for_member(baby) where code = 'allergies') like '%Bea%', 'prompt personalised';

  begin perform health.save_answers(hh, kid, 'not_yet_introduced', array['seafood']); raise exception 'TEST FAILED: inapplicable question accepted';
  exception when others then if sqlerrm <> 'question_not_applicable' then raise; end if; end;
  perform health.save_answers(hh, baby, 'not_yet_introduced', array['seafood','eggs']);
  assert (select count(*) from health.member_food_preferences where member_id = baby and kind = 'avoid' and deleted_at is null) = 2;

  -- completeness only counts applicable questions
  assert (select total_questions from health.v_member_profile_progress where member_id = kid) =
         (select total_questions from health.v_member_profile_progress where member_id = unk), 'older child and unknown age have the same question set';
  assert (select total_questions from health.v_member_profile_progress where member_id = baby) =
         (select total_questions from health.v_member_profile_progress where member_id = kid) + 1, 'infant has exactly one extra question';
  begin insert into hh.family_members(household_id,preferred_name,age_range) values (hh,'X','not_a_band'); raise exception 'TEST FAILED: bad age band';
  exception when foreign_key_violation then null; end;
  raise notice 'AGE TESTS PASSED';
end $$;
rollback;
