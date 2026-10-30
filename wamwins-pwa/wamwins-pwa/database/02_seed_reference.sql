-- Reference data + WAMWins Basic (Free) plan. Idempotent enough for first install.
insert into core.plans(id, code, name, tier_level) values (1, 'basic', 'WAMWins Basic', 1);   -- tiers 2-7: add rows when defined
insert into core.capabilities(code, description) values
 ('household.manual_setup','Manual household setup'),('family.profiles','Family member profiles'),
 ('health.food_requirements','Allergies, intolerances, dietary and health food requirements'),
 ('kitchen.setup','Manual kitchen, appliance and tool setup'),('inventory.manual','Manual inventory entry'),
 ('meals.matching','Meal matching and recommendations'),('meals.history','Meal and consumption history'),
 ('shopping.list','Shopping list'),('alerts.inventory','Use-soon and low-stock alerts'),
 ('household.multi_user','More than one user account per household'),
 ('inventory.capture.image','Add inventory from photos'),('inventory.capture.video','Add inventory from video'),
 ('inventory.scan.barcode','Add inventory by barcode'),('inventory.scan.receipt','Add inventory from receipts'),
 ('kitchen.auto_mapping','Automatic kitchen mapping'),('ai.recognition','AI food recognition');
insert into core.plan_capabilities select 1, code from core.capabilities
 where code in ('household.manual_setup','family.profiles','health.food_requirements','kitchen.setup','inventory.manual',
                'meals.matching','meals.history','shopping.list','alerts.inventory');
insert into core.plan_limits values (1,'user_seats',1),(1,'households_per_owner',1);   -- Free tier = 1 user

insert into ref.setup_steps values ('about_you','About You',1),('household','Your Household',2),('family_members','Family Members',3),
 ('food_needs','Food Needs',4),('kitchen','Your Kitchen',5),('appliances_tools','Appliances & Tools',6),
 ('inventory','Food Inventory',7),('meal_matching','Start Meal Matching',8);

insert into ref.units(code,name,symbol,dimension,to_base,system) values
 ('g','gram','g','mass',1,'metric'),('kg','kilogram','kg','mass',1000,'metric'),
 ('oz','ounce','oz','mass',28.349523125,'us'),('lb','pound','lb','mass',453.59237,'us'),
 ('ml','milliliter','ml','volume',1,'metric'),('l','liter','L','volume',1000,'metric'),
 ('fl_oz','fluid ounce','fl oz','volume',29.5735295625,'us'),('cup','cup','cup','volume',236.5882365,'us'),
 ('tbsp','tablespoon','tbsp','volume',14.78676478125,'us'),('tsp','teaspoon','tsp','volume',4.92892159375,'us'),
 ('pint','pint','pt','volume',473.176473,'us'),('quart','quart','qt','volume',946.352946,'us'),
 ('gallon','gallon','gal','volume',3785.411784,'us'),('each','each','ea','count',1,'both');

insert into ref.food_categories(code,name,sort_order) values
 ('produce','Produce',1),('protein','Protein',2),('dairy_eggs','Dairy & Eggs',3),('grains','Grains & Pasta',4),
 ('pantry','Pantry Staples',5),('beverages','Beverages',6),('frozen','Frozen',7),('snacks','Snacks',8);
insert into ref.food_categories(parent_id,code,name,sort_order)
 select p.id, v.code, v.name, v.ord from (values
  ('produce','vegetables','Vegetables',1),('produce','fruits','Fruits',2),
  ('protein','meat','Meat',1),('protein','poultry','Poultry',2),('protein','seafood','Seafood',3),('protein','legumes','Legumes',4),
  ('dairy_eggs','dairy','Dairy',1),('dairy_eggs','eggs','Eggs',2),
  ('pantry','oils_fats','Oils & Fats',1),('pantry','spices','Spices & Seasonings',2)) v(par,code,name,ord)
 join ref.food_categories p on p.code = v.par;

insert into ref.location_types(code,name,temperature,is_container) values
 ('pantry','Pantry','ambient',true),('shelf','Shelf','ambient',true),('refrigerator','Refrigerator','chilled',true),
 ('freezer','Freezer','frozen',true),('cabinet','Cabinets','ambient',true),('drawer','Drawers','ambient',true),
 ('kitchen_island','Kitchen Island','ambient',true),('countertop','Countertop Storage','ambient',true),
 ('spice_rack','Spice Rack','ambient',true),('garage_refrigerator','Garage Refrigerator','chilled',true),
 ('garage_freezer','Garage Freezer','frozen',true),('other','Other','ambient',true);
insert into ref.appliance_types(code,name) values
 ('refrigerator','Refrigerator'),('freezer','Freezer'),('range','Range'),('oven','Oven'),('microwave','Microwave'),
 ('dishwasher','Dishwasher'),('air_fryer','Air Fryer'),('slow_cooker','Slow Cooker'),('pressure_cooker','Pressure Cooker'),
 ('blender','Blender'),('food_processor','Food Processor'),('coffee_maker','Coffee Maker'),('toaster','Toaster'),
 ('rice_cooker','Rice Cooker'),('other','Other');
insert into ref.utensil_types(code,name,kind) values
 ('frying_pan','Frying Pan','cookware'),('saucepan','Saucepan','cookware'),('stockpot','Stockpot','cookware'),
 ('dutch_oven','Dutch Oven','cookware'),('baking_sheet','Baking Sheet','cookware'),('chef_knife','Chef Knife','tool'),
 ('cutting_board','Cutting Board','tool'),('tongs','Tongs','utensil'),('spatula','Spatula','utensil'),
 ('whisk','Whisk','utensil'),('measuring_cups','Measuring Cups','tool'),('storage_container','Food Storage Containers','container'),
 ('other','Other','tool');
insert into ref.nutrients(code,name,unit) values
 ('calories','Calories','kcal'),('protein','Protein','g'),('carbs','Carbohydrates','g'),('fat','Total fat','g'),
 ('sat_fat','Saturated fat','g'),('sugar','Sugar','g'),('fiber','Fiber','g'),('sodium','Sodium','mg');
insert into ref.allergens(code,name,kind) values
 ('milk','Milk','allergen'),('egg','Egg','allergen'),('fish','Fish','allergen'),('shellfish','Shellfish','allergen'),
 ('tree_nuts','Tree nuts','allergen'),('peanuts','Peanuts','allergen'),('wheat','Wheat','allergen'),('soy','Soy','allergen'),
 ('sesame','Sesame','allergen'),('lactose','Lactose','intolerance_trigger'),('gluten','Gluten','intolerance_trigger'),
 ('fructose','Fructose','intolerance_trigger'),('sulfites','Sulfites','intolerance_trigger');

insert into ref.dietary_requirement_types(code,name) values
 ('vegetarian','Vegetarian'),('vegan','Vegan'),('pescatarian','Pescatarian'),('gluten_free','Gluten-free'),
 ('dairy_free','Dairy-free'),('halal','Halal'),('kosher','Kosher');
insert into ref.dietary_requirement_exclusions(requirement_type_id, category_id)
 select t.id, c.id from (values ('vegetarian','meat'),('vegetarian','poultry'),('vegetarian','seafood'),
  ('vegan','meat'),('vegan','poultry'),('vegan','seafood'),('vegan','dairy'),('vegan','eggs'),
  ('pescatarian','meat'),('pescatarian','poultry'),('dairy_free','dairy')) v(d,c)
 join ref.dietary_requirement_types t on t.code = v.d join ref.food_categories c on c.code = v.c;
insert into ref.dietary_requirement_exclusions(requirement_type_id, allergen_id)
 select t.id, a.id from (values ('gluten_free','gluten'),('gluten_free','wheat'),('dairy_free','milk')) v(d,a)
 join ref.dietary_requirement_types t on t.code = v.d join ref.allergens a on a.code = v.a;

-- STARTER thresholds only; must be reviewed by a qualified nutrition professional before release. Not medical advice.
insert into ref.health_requirement_types(code,name) values
 ('low_sodium','Low sodium'),('low_sugar','Low sugar'),('low_sat_fat','Low saturated fat'),
 ('high_protein','High protein'),('high_fiber','High fiber');
insert into ref.health_requirement_rules(type_id,nutrient_id,comparator,threshold_per_serving)
 select t.id, n.id, v.cmp, v.th from (values ('low_sodium','sodium','max',600),('low_sugar','sugar','max',10),
  ('low_sat_fat','sat_fat','max',5),('high_protein','protein','min',20),('high_fiber','fiber','min',5)) v(t,n,cmp,th)
 join ref.health_requirement_types t on t.code = v.t join ref.nutrients n on n.code = v.n;

insert into ref.food_items(name,category_id,default_unit_id,default_location_type_id,shelf_life_days,is_system)
 select v.name, c.id, u.id, l.id, v.life, true from (values
  ('Eggs','eggs','each','refrigerator',28),('Whole milk','dairy','gallon','refrigerator',7),
  ('Cheddar cheese','dairy','oz','refrigerator',30),('Butter','dairy','lb','refrigerator',60),
  ('Chicken breast','poultry','lb','refrigerator',3),('Spinach','vegetables','oz','refrigerator',5),
  ('Tomatoes','vegetables','each','countertop',7),('Onion','vegetables','each','pantry',30),
  ('Rice','grains','lb','pantry',365),('Pasta','grains','lb','pantry',365),
  ('Peanut butter','pantry','oz','pantry',180),('Olive oil','oils_fats','fl_oz','pantry',365),
  ('Black beans','legumes','oz','pantry',365),('Salmon','seafood','lb','refrigerator',2)) v(name,cat,unit,loc,life)
 join ref.food_categories c on c.code = v.cat join ref.units u on u.code = v.unit join ref.location_types l on l.code = v.loc;
insert into ref.food_item_allergens(food_item_id, allergen_id, presence)
 select f.id, a.id, 'contains' from (values ('Eggs','egg'),('Whole milk','milk'),('Whole milk','lactose'),('Cheddar cheese','milk'),
  ('Cheddar cheese','lactose'),('Butter','milk'),('Pasta','wheat'),('Pasta','gluten'),('Peanut butter','peanuts'),('Salmon','fish')) v(i,a)
 join ref.food_items f on f.name = v.i and f.household_id is null join ref.allergens a on a.code = v.a;
