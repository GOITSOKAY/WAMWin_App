-- 09: classification tree, uses, materials, master item types, sizes, regional examples
insert into ref.item_classes(code,name,sort_order) values
 ('appliances','Appliances',1),('food_storage','Food Storage',2),('cookware','Cookware',3),('bakeware','Bakeware',4),
 ('utensils','Utensils & Tools',5),('cutlery','Cutlery & Flatware',6),('dinnerware','Dinnerware',7),('glassware','Glassware',8),
 ('serveware','Serveware',9),('facilities','Kitchen Facilities',10),('cleaning','Cleaning & Care',11);
insert into ref.item_classes(parent_id,code,name,sort_order)
 select p.id, v.code, v.name, v.ord from (values
  ('appliances','refrigeration','Refrigeration',1),('appliances','major_cooking','Cooking Appliances',2),
  ('appliances','small_appliances','Small Appliances',3),('appliances','beverage_appliances','Beverage Appliances',4),
  ('appliances','dishwashing','Dishwashing',5),
  ('food_storage','containers','Containers',1),('food_storage','jars_canisters','Jars & Canisters',2),('food_storage','bags_wraps','Bags & Wraps',3),
  ('cookware','pots_pans','Pots & Pans',1),('cookware','specialty_cookware','Specialty Cookware',2),
  ('utensils','knives_cutting','Knives & Cutting',1),('utensils','measuring','Measuring',2),
  ('utensils','mixing_prep','Mixing & Prep',3),('utensils','handheld_tools','Handheld Tools',4),
  ('dinnerware','plates','Plates',1),('dinnerware','bowls','Bowls',2),('dinnerware','cups_mugs','Cups & Mugs',3),
  ('glassware','wine_glasses','Wine Glasses',1),('glassware','tumblers','Tumblers & Water Glasses',2),
  ('glassware','beer_glassware','Beer Glassware',3),('glassware','spirits_cocktail','Spirits & Cocktail Glasses',4),
  ('glassware','pitchers_decanters','Pitchers & Decanters',5),('glassware','hot_drink_glass','Hot Drink Glassware',6),
  ('serveware','serving_dishes','Serving Dishes',1),('serveware','tea_coffee_service','Tea & Coffee Service',2),
  ('serveware','table_accessories','Table Accessories',3),
  ('facilities','fixtures','Fixtures & Surfaces',1),('facilities','waste_water','Waste & Water',2),('facilities','safety','Safety',3),
  ('cleaning','cleaning_tools','Cleaning Tools & Textiles',1)) v(par,code,name,ord)
 join ref.item_classes p on p.code = v.par;

insert into ref.item_uses(code,name,use_group) values
 ('cooking','Cooking','cooking'),('baking','Baking & roasting','cooking'),('reheating','Reheating','cooking'),
 ('food_prep','Food preparation','prep'),('measuring','Measuring','prep'),('beverage_making','Making beverages','prep'),
 ('food_storage','Food storage','storage'),('food_preservation','Keeping food fresh','storage'),
 ('serving','Serving','serving'),('dining','Dining','dining'),
 ('drinking_water','Water & soft drinks','drinking'),('drinking_wine','Wine','drinking'),('drinking_sparkling','Sparkling wine','drinking'),
 ('drinking_beer','Beer','drinking'),('drinking_spirits','Spirits','drinking'),('drinking_cocktails','Cocktails','drinking'),
 ('drinking_hot','Hot drinks','drinking'),
 ('cleaning','Cleaning','cleaning'),('waste_handling','Waste & recycling','cleaning'),('workspace','Work surface','other'),
 ('water_supply','Water supply','other'),('food_safety','Safety','safety');
insert into ref.materials(code,name) values
 ('glass','Glass'),('crystal','Crystal'),('stainless_steel','Stainless steel'),('cast_iron','Cast iron'),('enameled_cast_iron','Enameled cast iron'),
 ('nonstick','Nonstick coated'),('aluminum','Aluminum'),('copper','Copper'),('carbon_steel','Carbon steel'),('ceramic','Ceramic'),
 ('porcelain','Porcelain'),('stoneware','Stoneware'),('clay','Clay / earthenware'),('plastic','Plastic'),('silicone','Silicone'),
 ('wood','Wood'),('bamboo','Bamboo'),('melamine','Melamine'),('fabric','Fabric'),('gourd','Gourd');

create temp table seed_types as select * from (values
 ('refrigeration','refrigerator','Refrigerator','v',1,null,'food_preservation'),
 ('refrigeration','freezer','Freezer','v',1,null,'food_preservation'),
 ('refrigeration','wine_fridge','Wine Fridge','c',0,null,'food_preservation'),
 ('major_cooking','range','Range / Stove','n',1,null,'cooking'),('major_cooking','cooktop','Cooktop','n',0,null,'cooking'),
 ('major_cooking','oven','Oven','v',1,null,'baking'),('major_cooking','microwave','Microwave','v',1,null,'reheating'),
 ('major_cooking','range_hood','Range Hood','n',0,null,'cooking'),
 ('small_appliances','air_fryer','Air Fryer','v',1,null,'cooking'),('small_appliances','slow_cooker','Slow Cooker','v',1,null,'cooking'),
 ('small_appliances','pressure_cooker','Pressure Cooker','v',1,null,'cooking'),('small_appliances','rice_cooker','Rice Cooker','v',1,null,'cooking'),
 ('small_appliances','toaster','Toaster','n',1,null,'cooking'),('small_appliances','toaster_oven','Toaster Oven','n',0,null,'baking'),
 ('small_appliances','blender','Blender','v',1,null,'food_prep'),('small_appliances','food_processor','Food Processor','v',1,null,'food_prep'),
 ('small_appliances','stand_mixer','Stand Mixer','v',0,null,'food_prep'),('small_appliances','hand_mixer','Hand Mixer','n',0,null,'food_prep'),
 ('small_appliances','immersion_blender','Immersion Blender','n',0,null,'food_prep'),('small_appliances','waffle_maker','Waffle Maker','n',0,null,'cooking'),
 ('small_appliances','sandwich_press','Sandwich Press','n',0,null,'cooking'),('small_appliances','deep_fryer','Deep Fryer','v',0,null,'cooking'),
 ('small_appliances','bread_machine','Bread Machine','n',0,null,'baking'),('small_appliances','vacuum_sealer','Vacuum Sealer','n',0,null,'food_preservation'),
 ('small_appliances','raclette_grill','Raclette Grill','n',0,'DE,FR,CH,AT,NL,BE','cooking'),
 ('small_appliances','other_appliance','Other Appliance','n',0,null,'cooking'),
 ('beverage_appliances','coffee_maker','Coffee Maker','v',1,null,'beverage_making'),
 ('beverage_appliances','espresso_machine','Espresso Machine','n',0,null,'beverage_making'),
 ('beverage_appliances','electric_kettle','Electric Kettle','v',1,null,'beverage_making'),
 ('beverage_appliances','moka_pot','Moka Pot','v',0,'IT,ES,PT,FR,AR,UY,BR,CL,CO','beverage_making'),
 ('beverage_appliances','juicer','Juicer','n',0,null,'beverage_making'),
 ('dishwashing','dishwasher','Dishwasher','n',1,null,'cleaning'),
 ('containers','storage_container','Food Storage Container','v',1,null,'food_storage'),
 ('containers','glass_container','Glass Food Container','v',1,null,'food_storage'),
 ('containers','lunch_box','Lunch Box','v',0,null,'food_storage'),('containers','bread_box','Bread Box','n',0,null,'food_storage'),
 ('jars_canisters','mason_jar','Mason / Preserving Jar','v',1,null,'food_storage'),
 ('jars_canisters','canister','Canister','v',1,null,'food_storage'),('jars_canisters','spice_jar','Spice Jar','v',1,null,'food_storage'),
 ('jars_canisters','oil_dispenser','Oil / Vinegar Dispenser','v',0,null,'food_storage'),
 ('bags_wraps','freezer_bags','Freezer Bags','c',1,null,'food_preservation'),('bags_wraps','food_wrap','Food Wrap / Foil','n',0,null,'food_preservation'),
 ('pots_pans','frying_pan','Frying Pan','n',1,null,'cooking'),('pots_pans','nonstick_pan','Nonstick Pan','n',0,null,'cooking'),
 ('pots_pans','cast_iron_skillet','Cast Iron Skillet','n',0,null,'cooking'),('pots_pans','saute_pan','Sauté Pan','v',0,null,'cooking'),
 ('pots_pans','grill_pan','Grill Pan','n',0,null,'cooking'),('pots_pans','saucepan','Saucepan','v',1,null,'cooking'),
 ('pots_pans','stockpot','Stockpot','v',1,null,'cooking'),('pots_pans','dutch_oven','Dutch Oven','v',1,null,'cooking'),
 ('pots_pans','wok','Wok','v',0,null,'cooking'),('pots_pans','steamer_pot','Steamer','v',0,null,'cooking'),
 ('specialty_cookware','cazuela','Clay Pot (Cazuela)','v',0,'ES,PT,MX,AR,CL,CO,PE','cooking'),
 ('specialty_cookware','comal','Comal / Griddle Plate','n',0,'MX,GT,SV,HN,CO,VE,US','cooking'),
 ('specialty_cookware','paella_pan','Paella Pan','n',0,'ES,AR,UY,CL,PT,FR,IT','cooking'),
 ('specialty_cookware','crepe_pan','Crêpe Pan','n',0,'FR,BE,DE,CH,BR','cooking'),
 ('specialty_cookware','fondue_set','Fondue Set','n',0,'CH,FR,DE,AT,IT','cooking'),
 ('specialty_cookware','tortilla_press','Tortilla Press','n',0,'MX,GT,SV,HN,CO,US','food_prep'),
 ('bakeware','baking_sheet','Baking Sheet','n',1,null,'baking'),('bakeware','cake_pan','Cake Pan','v',1,null,'baking'),
 ('bakeware','loaf_pan','Loaf Pan','v',1,null,'baking'),('bakeware','muffin_tin','Muffin Tin','c',1,null,'baking'),
 ('bakeware','pie_dish','Pie Dish','v',0,null,'baking'),('bakeware','casserole_dish','Casserole Dish','v',1,null,'baking'),
 ('bakeware','roasting_pan','Roasting Pan','v',0,null,'baking'),('bakeware','cooling_rack','Cooling Rack','n',0,null,'baking'),
 ('bakeware','pizza_stone','Pizza Stone','n',0,null,'baking'),('bakeware','springform_pan','Springform Pan','v',0,null,'baking'),
 ('knives_cutting','chef_knife','Chef Knife','n',1,null,'food_prep'),('knives_cutting','paring_knife','Paring Knife','n',1,null,'food_prep'),
 ('knives_cutting','bread_knife','Bread Knife','n',0,null,'food_prep'),('knives_cutting','cutting_board','Cutting Board','n',1,null,'food_prep'),
 ('knives_cutting','kitchen_shears','Kitchen Shears','n',0,null,'food_prep'),('knives_cutting','mandoline','Mandoline','n',0,null,'food_prep'),
 ('measuring','measuring_cups','Measuring Cups','v',1,null,'measuring'),('measuring','measuring_spoons','Measuring Spoons','v',1,null,'measuring'),
 ('measuring','kitchen_scale','Kitchen Scale','m',1,null,'measuring'),('measuring','meat_thermometer','Meat Thermometer','n',0,null,'measuring'),
 ('measuring','kitchen_timer','Kitchen Timer','n',0,null,'measuring'),
 ('mixing_prep','mixing_bowl','Mixing Bowl','v',1,null,'food_prep'),('mixing_prep','whisk','Whisk','n',1,null,'food_prep'),
 ('mixing_prep','colander','Colander','n',1,null,'food_prep'),('mixing_prep','strainer','Strainer / Sieve','n',0,null,'food_prep'),
 ('mixing_prep','salad_spinner','Salad Spinner','n',0,null,'food_prep'),('mixing_prep','rolling_pin','Rolling Pin','n',0,null,'food_prep'),
 ('mixing_prep','mortar_pestle','Mortar & Pestle','n',0,null,'food_prep'),('mixing_prep','grater','Grater','n',1,null,'food_prep'),
 ('mixing_prep','peeler','Peeler','n',1,null,'food_prep'),('mixing_prep','citrus_juicer','Citrus Juicer (manual)','n',0,null,'food_prep'),
 ('mixing_prep','potato_masher','Potato Masher','n',0,null,'food_prep'),('mixing_prep','garlic_press','Garlic Press','n',0,null,'food_prep'),
 ('mixing_prep','funnel','Funnel','n',0,null,'food_prep'),
 ('handheld_tools','spatula','Spatula','n',1,null,'cooking'),('handheld_tools','wooden_spoon','Wooden Spoon','n',1,null,'cooking'),
 ('handheld_tools','ladle','Ladle','n',1,null,'cooking'),('handheld_tools','tongs','Tongs','n',1,null,'cooking'),
 ('handheld_tools','slotted_spoon','Slotted Spoon','n',0,null,'cooking'),('handheld_tools','can_opener','Can Opener','n',1,null,'food_prep'),
 ('handheld_tools','bottle_opener','Bottle Opener','n',0,null,'food_prep'),('handheld_tools','corkscrew','Corkscrew / Wine Opener','n',0,null,'food_prep'),
 ('handheld_tools','other_tool','Other Tool','n',0,null,'food_prep'),
 ('cutlery','dinner_fork','Dinner Fork','n',1,null,'dining'),('cutlery','salad_fork','Salad Fork','n',0,null,'dining'),
 ('cutlery','dinner_knife','Dinner Knife','n',1,null,'dining'),('cutlery','steak_knife','Steak Knife','n',0,null,'dining'),
 ('cutlery','teaspoon','Teaspoon','n',1,null,'dining'),('cutlery','soup_spoon','Soup / Tablespoon','n',1,null,'dining'),
 ('cutlery','dessert_spoon','Dessert Spoon','n',0,null,'dining'),('cutlery','chopsticks','Chopsticks','n',0,null,'dining'),
 ('plates','dinner_plate','Dinner Plate','n',1,null,'dining'),('plates','salad_plate','Salad / Lunch Plate','n',1,null,'dining'),
 ('plates','bread_plate','Bread / Side Plate','n',0,null,'dining'),('plates','dessert_plate','Dessert Plate','n',0,null,'dining'),
 ('plates','charger_plate','Charger Plate','n',0,null,'dining'),
 ('bowls','soup_bowl','Soup Bowl','v',1,null,'dining'),('bowls','cereal_bowl','Cereal Bowl','v',1,null,'dining'),
 ('bowls','pasta_bowl','Pasta Bowl','v',0,null,'dining'),('bowls','rice_bowl','Rice Bowl','v',0,null,'dining'),
 ('cups_mugs','mug','Mug','v',1,null,'drinking_hot'),('cups_mugs','teacup_saucer','Teacup & Saucer','v',0,null,'drinking_hot'),
 ('cups_mugs','espresso_cup','Espresso Cup','v',0,null,'drinking_hot'),
 ('cups_mugs','mate_gourd','Mate Gourd','v',0,'AR,UY,PY,BR,CL','drinking_hot'),
 ('cups_mugs','bombilla','Bombilla (Mate Straw)','n',0,'AR,UY,PY,BR,CL','drinking_hot'),
 ('wine_glasses','red_wine_glass','Red Wine Glass','v',1,null,'drinking_wine'),
 ('wine_glasses','white_wine_glass','White Wine Glass','v',1,null,'drinking_wine'),
 ('wine_glasses','champagne_flute','Champagne Flute','v',1,null,'drinking_sparkling'),
 ('wine_glasses','coupe_glass','Coupe Glass','v',0,null,'drinking_cocktails'),
 ('tumblers','water_tumbler','Water Tumbler','v',1,null,'drinking_water'),('tumblers','juice_glass','Juice Glass','v',0,null,'drinking_water'),
 ('tumblers','highball_glass','Highball Glass','v',0,null,'drinking_cocktails'),('tumblers','rocks_glass','Rocks / Old Fashioned Glass','v',0,null,'drinking_spirits'),
 ('tumblers','water_goblet','Water Goblet','v',0,null,'drinking_water'),
 ('beer_glassware','pint_glass','Pint Glass','v',0,null,'drinking_beer'),('beer_glassware','pilsner_glass','Pilsner Glass','v',0,null,'drinking_beer'),
 ('beer_glassware','beer_mug_stein','Beer Mug / Stein','v',0,null,'drinking_beer'),
 ('beer_glassware','weizen_glass','Wheat Beer Glass (Weizen)','v',0,'DE,AT,CH','drinking_beer'),
 ('spirits_cocktail','shot_glass','Shot Glass','v',0,null,'drinking_spirits'),('spirits_cocktail','martini_glass','Martini Glass','v',0,null,'drinking_cocktails'),
 ('spirits_cocktail','margarita_glass','Margarita Glass','v',0,null,'drinking_cocktails'),
 ('spirits_cocktail','brandy_snifter','Brandy Snifter','v',0,null,'drinking_spirits'),
 ('pitchers_decanters','water_pitcher','Water Pitcher','v',1,null,'serving'),('pitchers_decanters','wine_decanter','Wine Decanter','v',0,null,'serving'),
 ('pitchers_decanters','carafe','Carafe','v',0,null,'serving'),
 ('hot_drink_glass','glass_mug','Glass Mug (coffee / tea)','v',0,null,'drinking_hot'),
 ('serving_dishes','serving_platter','Serving Platter','n',1,null,'serving'),('serving_dishes','serving_bowl','Serving Bowl','v',1,null,'serving'),
 ('serving_dishes','cake_stand','Cake Stand','n',0,null,'serving'),('serving_dishes','bread_basket','Bread Basket','n',0,null,'serving'),
 ('serving_dishes','butter_dish','Butter Dish','n',0,null,'serving'),('serving_dishes','gravy_boat','Gravy Boat','v',0,null,'serving'),
 ('tea_coffee_service','teapot','Teapot','v',0,null,'drinking_hot'),('tea_coffee_service','coffee_pot','Coffee Pot','v',0,null,'drinking_hot'),
 ('tea_coffee_service','creamer_sugar','Creamer & Sugar Bowl','n',0,null,'serving'),
 ('tea_coffee_service','thermal_carafe','Thermal Carafe','v',0,null,'drinking_hot'),
 ('table_accessories','salt_pepper_shakers','Salt & Pepper Shakers','n',1,null,'dining'),('table_accessories','trivet','Trivet','n',0,null,'serving'),
 ('table_accessories','serving_tray','Serving Tray','n',0,null,'serving'),
 ('fixtures','kitchen_sink','Kitchen Sink','n',1,null,'cleaning'),('fixtures','countertop','Countertop Workspace','n',1,null,'workspace'),
 ('fixtures','kitchen_island','Kitchen Island','n',0,null,'workspace'),('fixtures','built_in_pantry','Built-in Pantry','n',0,null,'food_storage'),
 ('fixtures','built_in_cabinets','Built-in Cabinets','n',1,null,'food_storage'),('fixtures','dining_table','Dining Table','n',0,null,'dining'),
 ('fixtures','bar_counter','Bar / Breakfast Counter','n',0,null,'dining'),
 ('waste_water','trash_bin','Trash Bin','v',1,null,'waste_handling'),('waste_water','recycling_bin','Recycling Bin','v',1,null,'waste_handling'),
 ('waste_water','compost_bin','Compost Bin','v',0,null,'waste_handling'),('waste_water','garbage_disposal','Garbage Disposal','n',0,null,'waste_handling'),
 ('waste_water','water_filter','Water Filter','n',0,null,'water_supply'),
 ('safety','fire_extinguisher','Fire Extinguisher','n',0,null,'food_safety'),('safety','smoke_detector','Smoke Detector','n',0,null,'food_safety'),
 ('safety','fire_blanket','Fire Blanket','n',0,null,'food_safety'),
 ('cleaning_tools','dish_rack','Dish Rack','n',0,null,'cleaning'),('cleaning_tools','dish_brush','Dish Brush / Sponge','n',0,null,'cleaning'),
 ('cleaning_tools','dish_towels','Dish Towels','n',1,null,'cleaning'),('cleaning_tools','oven_mitts','Oven Mitts / Pot Holders','n',1,null,'food_safety')
) v(cls,code,name,dim,com,reg,use);

insert into ref.kitchen_item_types(class_id, code, name, capacity_dimension, is_common, regions)
 select c.id, s.code, s.name, case s.dim when 'v' then 'volume' when 'm' then 'mass' when 'c' then 'count' else 'none' end,
        s.com = 1, string_to_array(s.reg, ',')
 from seed_types s join ref.item_classes c on c.code = s.cls;
insert into ref.kitchen_item_type_uses(type_id, use_id, is_primary)
 select t.id, u.id, true from seed_types s join ref.kitchen_item_types t on t.code = s.code join ref.item_uses u on u.code = s.use;
insert into ref.kitchen_item_type_uses(type_id, use_id, is_primary)
 select t.id, u.id, false from (values
  ('highball_glass','drinking_water'),('rocks_glass','drinking_cocktails'),('coupe_glass','drinking_sparkling'),('water_goblet','drinking_wine'),
  ('glass_mug','drinking_beer'),('wine_decanter','drinking_wine'),('water_pitcher','drinking_water'),('carafe','drinking_wine'),
  ('mixing_bowl','serving'),('casserole_dish','serving'),('dutch_oven','baking'),('cast_iron_skillet','baking'),('air_fryer','reheating'),
  ('microwave','cooking'),('mason_jar','food_preservation'),('storage_container','food_preservation'),('glass_container','reheating'),
  ('glass_container','baking'),('espresso_cup','drinking_hot'),('soup_bowl','serving'),('serving_bowl','dining'),('kitchen_island','food_prep'),
  ('countertop','food_prep'),('freezer','food_storage'),('refrigerator','food_storage'),('toaster_oven','cooking'),('moka_pot','drinking_hot'),
  ('teapot','serving'),('coffee_pot','serving')) v(tc,uc)
 join ref.kitchen_item_types t on t.code = v.tc join ref.item_uses u on u.code = v.uc
 where not exists (select 1 from ref.kitchen_item_type_uses x where x.type_id = t.id and x.use_id = u.id);
-- appliances that recipes can require
update ref.kitchen_item_types t set appliance_type_id = a.id from ref.appliance_types a
 where a.code = t.code and t.code <> 'other';
update ref.kitchen_item_types t set appliance_type_id = (select id from ref.appliance_types where code = 'other') where t.code = 'other_appliance';

insert into ref.kitchen_item_sizes(type_id, code, label, capacity_value, capacity_unit_id, sort_order)
 select t.id, v.code, v.label, v.cap, u.id, v.ord from (values
  ('red_wine_glass','std','Standard 12 oz',12,'fl_oz',1),('red_wine_glass','large','Large 20 oz',20,'fl_oz',2),('red_wine_glass','std_ml','Standard 350 ml',350,'ml',3),
  ('white_wine_glass','std','Standard 10 oz',10,'fl_oz',1),('white_wine_glass','std_ml','Standard 300 ml',300,'ml',2),
  ('champagne_flute','std','Standard 6 oz',6,'fl_oz',1),('champagne_flute','std_ml','Standard 180 ml',180,'ml',2),
  ('water_tumbler','std','Standard 12 oz',12,'fl_oz',1),('water_tumbler','large','Large 16 oz',16,'fl_oz',2),('water_tumbler','std_ml','Standard 350 ml',350,'ml',3),
  ('highball_glass','std','Standard 12 oz',12,'fl_oz',1),('rocks_glass','std','Standard 10 oz',10,'fl_oz',1),
  ('pint_glass','us','US pint 16 oz',16,'fl_oz',1),('pint_glass','imperial','Imperial pint 568 ml',568,'ml',2),
  ('pilsner_glass','std_ml','Standard 400 ml',400,'ml',1),('shot_glass','std','Standard 1.5 oz',1.5,'fl_oz',1),
  ('martini_glass','std','Standard 7 oz',7,'fl_oz',1),('mug','std','Standard 12 oz',12,'fl_oz',1),('mug','std_ml','Standard 350 ml',350,'ml',2),
  ('stockpot','6qt','6 quart',6,'quart',1),('stockpot','8qt','8 quart',8,'quart',2),('stockpot','12qt','12 quart',12,'quart',3),
  ('stockpot','5l','5 liter',5,'l',4),('stockpot','8l','8 liter',8,'l',5),
  ('saucepan','1qt','1 quart',1,'quart',1),('saucepan','2qt','2 quart',2,'quart',2),('saucepan','3qt','3 quart',3,'quart',3),
  ('saucepan','1l','1 liter',1,'l',4),('saucepan','2l','2 liter',2,'l',5),
  ('dutch_oven','5_5qt','5.5 quart',5.5,'quart',1),('dutch_oven','5l','5 liter',5,'l',2),
  ('refrigerator','compact','Compact (about 150 L)',150,'l',1),('refrigerator','standard','Standard (about 400 L)',400,'l',2),('refrigerator','large','Large (about 600 L)',600,'l',3),
  ('freezer','chest_small','Small (about 150 L)',150,'l',1),('freezer','chest_large','Large (about 300 L)',300,'l',2),
  ('mixing_bowl','med','Medium 3 quart',3,'quart',1),('mixing_bowl','large','Large 5 quart',5,'quart',2),('mixing_bowl','3l','3 liter',3,'l',3),
  ('water_pitcher','2qt','2 quart',2,'quart',1),('water_pitcher','2l','2 liter',2,'l',2),('wine_decanter','std','Standard 750 ml',750,'ml',1)) v(tc,code,label,cap,uc,ord)
 join ref.kitchen_item_types t on t.code = v.tc join ref.units u on u.code = v.uc;
insert into ref.kitchen_item_sizes(type_id, code, label, sort_order)
 select t.id, v.code, v.label, v.ord from (values
  ('baking_sheet','half_us','Half sheet 18 x 13 in',1),('baking_sheet','quarter_us','Quarter sheet 13 x 9 in',2),('baking_sheet','std_eu','Standard 40 x 30 cm',3),
  ('frying_pan','8in','8 in / 20 cm',1),('frying_pan','10in','10 in / 26 cm',2),('frying_pan','12in','12 in / 30 cm',3),
  ('dinner_plate','std','Standard 10–11 in / 26–28 cm',1),('dinner_plate','small','Small 9 in / 23 cm',2)) v(tc,code,label,ord)
 join ref.kitchen_item_types t on t.code = v.tc;

-- Regional names (examples; extend as content grows)
insert into ref.i18n_labels(entity, entity_id, locale, value)
 select 'food_item', f.id, v.loc, v.val from (values
  ('Eggs','es','Huevos'),('Eggs','pt-BR','Ovos'),('Eggs','fr','Œufs'),('Eggs','de','Eier'),
  ('Tomatoes','es','Tomates'),('Tomatoes','pt-BR','Tomates'),('Tomatoes','de','Tomaten'),
  ('Rice','es','Arroz'),('Rice','pt-BR','Arroz'),('Rice','fr','Riz'),('Rice','de','Reis'),
  ('Whole milk','es','Leche entera'),('Whole milk','pt-BR','Leite integral'),('Whole milk','de','Vollmilch'),
  ('Pasta','de','Nudeln'),('Pasta','pt-BR','Macarrão')) v(n,loc,val)
 join ref.food_items f on f.name = v.n and f.household_id is null;
insert into ref.i18n_labels(entity, entity_id, locale, value)
 select 'kitchen_item_type', t.id, v.loc, v.val from (values
  ('frying_pan','es','Sartén'),('frying_pan','pt-BR','Frigideira'),('frying_pan','de','Bratpfanne'),('frying_pan','fr','Poêle'),
  ('red_wine_glass','es','Copa de vino tinto'),('red_wine_glass','pt-BR','Taça de vinho tinto'),('red_wine_glass','de','Rotweinglas'),
  ('stockpot','es','Olla grande'),('stockpot','pt-BR','Panela de caldo'),('stockpot','de','Suppentopf'),
  ('refrigerator','es','Refrigerador'),('refrigerator','pt-BR','Geladeira'),('refrigerator','de','Kühlschrank'),
  ('mug','es','Taza'),('mug','pt-BR','Caneca'),('mug','de','Tasse')) v(c,loc,val)
 join ref.kitchen_item_types t on t.code = v.c;
insert into ref.food_item_packages(food_item_id, country_code, label, size_qty, unit_id)
 select f.id, v.cc, v.lbl, v.q, u.id from (values
  ('Pasta','US','1 lb box',1,'lb'),('Pasta','DE','500 g pack',500,'g'),('Pasta','BR','500 g pack',500,'g'),
  ('Whole milk','US','1 gallon jug',1,'gallon'),('Whole milk','DE','1 liter carton',1,'l'),('Whole milk','BR','1 liter carton',1,'l'),
  ('Rice','US','2 lb bag',2,'lb'),('Rice','BR','5 kg bag',5,'kg'),('Rice','DE','1 kg bag',1,'kg'),
  ('Eggs','US','1 dozen',12,'each'),('Eggs','DE','10-pack',10,'each'),('Eggs','BR','1 dozen',12,'each')) v(n,cc,lbl,q,uc)
 join ref.food_items f on f.name = v.n and f.household_id is null join ref.units u on u.code = v.uc;
drop table seed_types;
