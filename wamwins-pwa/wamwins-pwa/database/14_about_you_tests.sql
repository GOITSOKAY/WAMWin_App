\set ON_ERROR_STOP on
begin;
insert into core.users(id,email,first_name) values ('11111111-1111-1111-1111-111111111111','maria@example.com','Maria'),('22222222-2222-2222-2222-222222222222','other@example.com','Sam');
set local role wam_app;
set local app.user_id = '11111111-1111-1111-1111-111111111111';
do $$
declare hh uuid;
begin
  hh := core.create_household('11111111-1111-1111-1111-111111111111','The Smith Family');
  perform core.save_about_you(hh, ' Mari ', 'parent', array['decide_what_to_cook','reduce_food_waste']);
  assert (select preferred_name from hh.family_members where household_id=hh and is_account_holder) = 'Mari', 'name saved and trimmed';
  assert (select household_role from core.household_memberships where household_id=hh) = 'parent';
  assert (select count(*) from core.membership_goals where household_id=hh) = 2;
  assert (select status from core.setup_progress where household_id=hh and step_code='about_you') = 'done';
  perform core.save_about_you(hh, 'Mari', 'caregiver', array['eat_healthier']);
  assert (select count(*) from core.membership_goals where household_id=hh) = 1 and (select household_role from core.household_memberships where household_id=hh) = 'caregiver', 'answers replaced';
  begin perform core.save_about_you(hh,'Mari','astronaut',array[]::text[]); raise exception 'TEST FAILED: bad role'; exception when check_violation then null; end;
  begin perform core.save_about_you(hh,'Mari','parent',array['nope']); raise exception 'TEST FAILED: bad goal'; exception when others then if sqlerrm <> 'unknown_goal' then raise; end if; end;
  begin perform core.save_about_you(hh,'  ','parent',array[]::text[]); raise exception 'TEST FAILED: blank name'; exception when others then if sqlerrm <> 'name_required' then raise; end if; end;
  perform core.set_setup_step(hh,'kitchen','skipped');
  assert (select status from core.setup_progress where household_id=hh and step_code='kitchen') = 'skipped';
  begin perform core.set_setup_step(hh,'kitchen','finished'); raise exception 'TEST FAILED: bad status'; exception when others then if sqlerrm <> 'invalid_status' then raise; end if; end;
  perform set_config('app.user_id','22222222-2222-2222-2222-222222222222',true);
  begin perform core.save_about_you(hh,'Intruder','parent',array[]::text[]); raise exception 'TEST FAILED: non-member allowed'; exception when others then if sqlerrm <> 'not_a_member' then raise; end if; end;
  assert (select count(*) from core.membership_goals) = 0, 'RLS leak: goals';
  raise notice 'ABOUT-YOU TESTS PASSED';
end $$;
rollback;
