\set ON_ERROR_STOP on
begin;
insert into core.users(id,email,first_name) values ('11111111-1111-1111-1111-111111111111','maria@example.com','Maria');
set local role wam_app;
set local app.user_id = '11111111-1111-1111-1111-111111111111';
do $$
declare hh uuid; leo uuid; n int; q record;
begin
  hh := core.create_household('11111111-1111-1111-1111-111111111111','The Smith Family');
  insert into hh.family_members(household_id,preferred_name,relationship) values (hh,'Leo','child') returning id into leo;
  assert (select is_complete from health.v_member_profile_progress where member_id = leo) = false, 'new profile starts incomplete';

  perform health.save_answers(hh, leo, 'allergies', array['peanuts','egg']);
  assert (select count(*) from health.member_allergies where member_id=leo and deleted_at is null) = 2, 'two allergies from answers';
  insert into health.member_allergies(household_id,member_id,allergen_id) select hh, leo, id from ref.allergens where code='fish';  -- manual row
  perform health.save_answers(hh, leo, 'allergies', array['peanuts','milk']);
  assert (select count(*) from health.member_allergies a join ref.allergens x on x.id=a.allergen_id where a.member_id=leo and a.deleted_at is null and x.code='egg') = 0, 'removed answer must retire derived row';
  assert (select count(*) from health.member_allergies a join ref.allergens x on x.id=a.allergen_id where a.member_id=leo and a.deleted_at is null and x.code in ('peanuts','milk','fish')) = 3, 'manual row must survive';
  perform health.save_answers(hh, leo, 'allergies', array['peanuts','egg']);    -- revive after soft delete
  assert (select count(*) from health.member_allergies a join ref.allergens x on x.id=a.allergen_id where a.member_id=leo and a.deleted_at is null and x.code='egg') = 1, 'revived';

  begin perform health.save_answers(hh, leo, 'allergies', array['peanuts','none']); raise exception 'TEST FAILED: none not exclusive';
  exception when others then if sqlerrm <> 'none_is_exclusive' then raise; end if; end;
  begin perform health.save_answers(hh, leo, 'allergies', array['not_a_thing']); raise exception 'TEST FAILED: bad option';
  exception when others then if sqlerrm <> 'unknown_option' then raise; end if; end;

  perform health.save_answers(hh, leo, 'diet', array['vegetarian']);
  perform health.save_answers(hh, leo, 'health_food', array['low_sodium']);
  perform health.save_answers(hh, leo, 'dislikes', array['seafood']);
  assert (select count(*) from health.member_dietary_requirements where member_id=leo and deleted_at is null) = 1;
  assert (select count(*) from health.member_health_requirements where member_id=leo and deleted_at is null) = 1;
  assert (select count(*) from health.member_food_preferences where member_id=leo and kind='dislike' and deleted_at is null) = 1;

  -- progress: complete only when every active question has an answer ("None of these" counts)
  for q in select code from health.questions_for_member(leo) loop
    if not exists (select 1 from health.v_member_question_status where member_id=leo and question_code=q.code and answered) then
      perform health.save_answers(hh, leo, q.code, array['none']);
    end if;
  end loop;
  assert (select is_complete from health.v_member_profile_progress where member_id = leo), 'profile should now be complete';
  raise notice 'PROFILING TESTS PASSED';
end $$;
rollback;
