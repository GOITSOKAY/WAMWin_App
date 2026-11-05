import { REF } from './reference.js';

/** The five inquiry steps of the entry module (infographic #1), in order. */
export const STEPS = [
  { id: 'about', title: 'About you', lead: 'A few quick questions so WAMWins fits the way you cook.', section: 'USER' },
  { id: 'household', title: 'Your household', lead: 'Tell us who you’re planning for and which kitchens you have.', section: 'HOUSEHOLD' },
  { id: 'kitchens', title: 'Kitchens & equipment', lead: 'Count what you actually have. WAMWins only sets up what you choose here.', section: 'KITCHEN' },
  { id: 'family', title: 'Family & health', lead: 'Allergies and diets keep meal suggestions safe for everyone at your table.', section: 'FAMILY' },
  { id: 'food', title: 'Food on hand', lead: 'Add a few things you have now, or skip and add food later.', section: 'INVENTORY' },
];
export const QUESTIONNAIRE = { code: 'HOUSEHOLD_PROFILE', version: 1 };

export const COOKING_ROLE = [
  { code: 'ME', name: 'Mostly me' }, { code: 'SHARED', name: 'We share it' }, { code: 'OTHER', name: 'Someone else does' }];
export const SKILL = [
  { code: 'BEGINNER', name: 'Just starting out', hint: 'Simple recipes with clear steps' },
  { code: 'COMFORTABLE', name: 'Comfortable', hint: 'Everyday cooking is fine' },
  { code: 'CONFIDENT', name: 'Confident cook', hint: 'Happy to try anything' }];
export const MEASURES = [{ code: 'METRIC', name: 'Metric', hint: 'grams, millilitres' }, { code: 'IMPERIAL', name: 'Imperial', hint: 'ounces, cups' }];
export const KITCHEN_TYPES = [
  { code: 'MAIN', name: 'Main kitchen' }, { code: 'SECONDARY', name: 'Second kitchen' }, { code: 'OUTDOOR', name: 'Outdoor kitchen' },
  { code: 'BASEMENT', name: 'Basement kitchen' }, { code: 'OTHER', name: 'Other kitchen' }];
export const RELATIONSHIPS = [
  { code: 'SELF', name: 'Me' }, { code: 'PARTNER', name: 'Partner' }, { code: 'CHILD', name: 'Child' }, { code: 'PARENT', name: 'Parent' },
  { code: 'SIBLING', name: 'Sibling' }, { code: 'GRANDPARENT', name: 'Grandparent' }, { code: 'RELATIVE', name: 'Relative' },
  { code: 'CAREGIVER', name: 'Helper or caregiver' }, { code: 'OTHER', name: 'Other' }];
export const AGE_BANDS = [
  { code: 'INFANT', name: 'Baby' }, { code: 'TODDLER', name: 'Toddler' }, { code: 'CHILD', name: 'Child' }, { code: 'TEEN', name: 'Teen' },
  { code: 'ADULT', name: 'Adult' }, { code: 'SENIOR', name: 'Senior' }];
const byClass = (c) => REF.equipment.filter(e => e.equipment_class === c).map(e => ({ code: e.code, name: e.name }));
export const APPLIANCES = byClass('APPLIANCE').filter(a => !['REFRIGERATOR', 'UPRIGHT_FREEZER', 'CHEST_FREEZER'].includes(a.code)); // fridges are counted as storage
export const COOKWARE = byClass('COOKWARE');
export const UTENSILS = byClass('UTENSIL');
export const STORAGE_TYPES = REF.storageTypes.map(s => ({ code: s.code, name: s.name, zone: s.temperature_zone }));
export const ALLERGENS = REF.allergens.map(a => ({ code: a.code, name: a.name }));
export const DIETS = REF.dietaryPatterns.map(d => ({ code: d.code, name: d.name }));
export const HEALTH_GOALS = REF.healthRequirements.map(r => ({ code: r.code, name: r.name }));
export const CUISINES = REF.cuisines.filter(c => c.code !== 'OTHER').map(c => ({ code: c.code, name: c.name }));
export const STORAGE_HINT = { REFRIGERATOR: 'Fridge', FREEZER: 'Upright or top freezer', CHEST_FREEZER: 'Lift-top freezer', HANGING_CABINET: 'Wall cabinet', GROUND_CABINET: 'Base cabinet under the counter' };
