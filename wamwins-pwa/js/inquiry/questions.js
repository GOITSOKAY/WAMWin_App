import { REF } from './reference.js';

/**
 * Entry Module v2: seven modules (the seventh is the review). Each module is its own lazily loaded screen.
 * Option lists come from the generated reference data (database/seed-data) wherever the database has them.
 */
export const QUESTIONNAIRE = { code: 'HOUSEHOLD_PROFILE', version: 2 };
export const STEPS = [
  { id: 'about', title: 'About You', lead: 'A few questions about you and your household, so WAMWins fits the way your home runs.', section: 'USER' },
  { id: 'health', title: 'Health Profiles', lead: 'Dietary needs help keep meal suggestions safe for everyone at your table.', section: 'HEALTH' },
  { id: 'kitchens', title: 'Kitchens & Storages', lead: 'Add each kitchen and where you keep food. WAMWins sets up only what you choose.', section: 'KITCHEN' },
  { id: 'appliances', title: 'Kitchen Appliances', lead: 'Tick the appliances you have. Details are optional and can be added any time.', section: 'EQUIPMENT' },
  { id: 'kitchenware', title: 'Utensils & Kitchenware', lead: 'Tick what you have and how many. You can skip this and add it later.', section: 'EQUIPMENT' },
  { id: 'food', title: 'Food Inventories', lead: 'Add food you have now, or skip and add food later from your inventory.', section: 'INVENTORY' },
  { id: 'review', title: 'Review My Household Entries', lead: 'Check your entries. WAMWins saves only what you see here.', section: 'REVIEW' },
];
export const ORDER = STEPS.map(s => s.id);
import { V1_STEP_MAP as STEP_MAP } from './step-map.js';
export const V1_STEP_MAP = STEP_MAP;

export const COOKING_ROLE = [{ code: 'ME', name: 'Mostly me' }, { code: 'SHARED', name: 'We share it' }, { code: 'OTHER', name: 'Someone else does' }];
export const SKILL = [
  { code: 'BEGINNER', name: 'Just starting out', hint: 'Simple recipes with clear steps' },
  { code: 'COMFORTABLE', name: 'Comfortable', hint: 'Everyday cooking is fine' },
  { code: 'CONFIDENT', name: 'Confident cook', hint: 'Happy to try anything' }];
// U.S. launch market: U.S. customary is the default; metric stays selectable.
export const MEASURES = [{ code: 'IMPERIAL', name: 'U.S. customary', hint: 'oz, lb, cups, tbsp, tsp' }, { code: 'METRIC', name: 'Metric', hint: 'grams, kilograms, milliliters, liters' }];
export const DEFAULT_MEASURES = 'IMPERIAL';
export const HOUSEHOLD_ROLES = REF.householdRoles;
export const KITCHEN_KINDS = REF.kitchenKinds;
export const RELATIONSHIPS = [
  { code: 'SELF', name: 'Me' }, { code: 'PARTNER', name: 'Spouse / Partner' }, { code: 'CHILD', name: 'Child' }, { code: 'PARENT', name: 'Parent' },
  { code: 'SIBLING', name: 'Sibling' }, { code: 'GRANDPARENT', name: 'Grandparent' }, { code: 'RELATIVE', name: 'Relative' },
  { code: 'CAREGIVER', name: 'Caregiver' }, { code: 'GUEST', name: 'Frequent guest' }, { code: 'OTHER', name: 'Other' }];
export const AGE_BANDS = [
  { code: 'INFANT', name: 'Baby' }, { code: 'TODDLER', name: 'Toddler' }, { code: 'CHILD', name: 'Child' }, { code: 'TEEN', name: 'Teen' },
  { code: 'ADULT', name: 'Adult' }, { code: 'SENIOR', name: 'Senior' }];
export const MEAL_CONTEXTS = [{ code: 'BREAKFAST', name: 'Breakfast' }, { code: 'LUNCH', name: 'Lunch' }, { code: 'DINNER', name: 'Dinner' },
  { code: 'SNACK', name: 'Between meals / snacks' }, { code: 'BEVERAGE', name: 'Drinks / beverages' }];
export const STORAGE_TYPES = REF.storageTypes.map(s => ({ code: s.code, name: s.name, zone: s.temperature_zone, applianceBacked: !!s.is_appliance_backed }));
export const ALLERGENS = REF.allergens.map(a => ({ code: a.code, name: a.name }));
export const DIETS = REF.dietaryPatterns.map(d => ({ code: d.code, name: d.name }));
export const HEALTH_GOALS = REF.healthRequirements.map(r => ({ code: r.code, name: r.name }));
export const APPLIANCE_TYPES = REF.equipment.filter(e => e.equipment_class === 'APPLIANCE' && e.code !== 'CUSTOM_APPLIANCE')
  .sort((a, b) => (a.size_rank ?? 99) - (b.size_rank ?? 99));
export const KITCHENWARE_CATEGORIES = [{ code: 'DINNERWARE', name: 'Dinnerware' }, { code: 'FLATWARE', name: 'Silverware / Flatware' },
  { code: 'COOKWARE', name: 'Cookware and Cooking Tools' }, { code: 'GLASSWARE', name: 'Glassware' }, { code: 'OTHER', name: 'Others' }];
export const CONDITIONS = [{ code: 'NEW', name: 'New' }, { code: 'GOOD', name: 'Good' }, { code: 'FAIR', name: 'Fair' }, { code: 'POOR', name: 'Poor' }];
export const APPLIANCE_CONDITIONS = [{ code: 'WORKING', name: 'Working' }, { code: 'NEEDS_REPAIR', name: 'Needs repair' }, { code: 'OUT_OF_SERVICE', name: 'Not working' }];
export const STORAGE_HINT = { REFRIGERATOR: 'Main fresh-food compartment', REFRIGERATOR_FREEZER: 'The freezer part of your refrigerator', FREEZER: 'Stand-alone upright freezer',
  CHEST_FREEZER: 'Lift-top freezer', HANGING_CABINET: 'Mounted on the wall', GROUND_CABINET: 'Under the countertop', WALK_IN_PANTRY: 'A pantry you can walk into' };

// v1 lists (only the v1 -> v2 adapter uses these)
export const LEGACY_KITCHEN_TYPES = [
  { code: 'MAIN', name: 'Main kitchen' }, { code: 'SECONDARY', name: 'Second kitchen' }, { code: 'OUTDOOR', name: 'Outdoor kitchen' },
  { code: 'BASEMENT', name: 'Basement kitchen' }, { code: 'OTHER', name: 'Other kitchen' }];
