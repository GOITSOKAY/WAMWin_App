/* Reference data (master data). Mirrors wamwins-db ref.* tables. Lazily initialised. */
W.def('ref', function(){
const CATS={produce:{n:'Produce'},vegetables:{n:'Vegetables',p:'produce'},fruits:{n:'Fruits',p:'produce'},protein:{n:'Protein'},meat:{n:'Meat',p:'protein'},poultry:{n:'Poultry',p:'protein'},seafood:{n:'Seafood',p:'protein'},legumes:{n:'Legumes',p:'protein'},dairy_eggs:{n:'Dairy & Eggs'},dairy:{n:'Dairy',p:'dairy_eggs'},eggs:{n:'Eggs',p:'dairy_eggs'},grains:{n:'Grains & Pasta'},pantry:{n:'Pantry Staples'},oils_fats:{n:'Oils & Fats',p:'pantry'},spices:{n:'Spices & Seasonings',p:'pantry'},beverages:{n:'Beverages'},frozen:{n:'Frozen'},snacks:{n:'Snacks'}};
const LEAF_CATS=['vegetables','fruits','meat','poultry','seafood','legumes','dairy','eggs','grains','oils_fats','spices','beverages','frozen','snacks'];
const ALLERGENS={peanuts:'Peanuts',tree_nuts:'Tree nuts',milk:'Milk',egg:'Egg',fish:'Fish',shellfish:'Shellfish',soy:'Soy',wheat:'Wheat',sesame:'Sesame'};
const INTOL={lactose:'Lactose',gluten:'Gluten',fructose:'Fructose',sulfites:'Sulfites'};
const DIETS={vegetarian:'Vegetarian',vegan:'Vegan',pescatarian:'Pescatarian',gluten_free:'Gluten-free',dairy_free:'Dairy-free',halal:'Halal',kosher:'Kosher'};
/* exclusions: categories c, allergens a, foods f */
const DIET_EX={vegetarian:{c:['meat','poultry','seafood']},vegan:{c:['meat','poultry','seafood','dairy','eggs'],f:['honey']},pescatarian:{c:['meat','poultry']},gluten_free:{a:['gluten','wheat']},dairy_free:{c:['dairy'],a:['milk']},halal:{f:['pork','ham','sausage']},kosher:{f:['pork','ham','sausage','shrimp']}};
/* STARTER thresholds per serving (from 02_seed_reference.sql) — review with a nutrition professional. Not medical advice. */
const HEALTH={low_sodium:{n:'Low sodium',k:'sodium',cmp:'max',t:600,u:'mg'},low_sugar:{n:'Low sugar',k:'sugar',cmp:'max',t:10,u:'g'},low_sat_fat:{n:'Low saturated fat',k:'sat',cmp:'max',t:5,u:'g'},high_protein:{n:'High protein',k:'protein',cmp:'min',t:20,u:'g'},high_fiber:{n:'High fiber',k:'fiber',cmp:'min',t:5,u:'g'}};
const NUTR={cal:'Calories',protein:'Protein',sat:'Saturated fat',sugar:'Sugar',fiber:'Fiber',sodium:'Sodium'};
const AGE_BANDS=[['under_1','Under 1',0,1],['age_1_2','1–2',1,3],['age_3_5','3–5',3,6],['age_6_12','6–12',6,13],['age_13_17','13–17',13,18],['age_18_64','18–64',18,65],['age_65_plus','65 and over',65,150]];
const RELS={self:'Me',spouse_partner:'Spouse / Partner',child:'Child',parent:'Parent',grandparent:'Grandparent',sibling:'Sibling',relative:'Other relative',other:'Other'};
const ROLES={parent:'Parent',homemaker:'Homemaker',spouse_partner:'Spouse / Partner',household_manager:'Household Manager',kitchen_manager:'Kitchen Manager',caregiver:'Caregiver',family_member:'Family Member',other:'Other'};
const GOALS={decide_what_to_cook:'Decide what to cook',manage_inventory:'Manage food inventory',eat_healthier:'Eat healthier',support_family_requirements:'Support family food needs',reduce_food_waste:'Reduce food waste',organize_kitchen:'Organize the kitchen',reduce_grocery_spend:'Fewer grocery runs'};
const STEPS=[['about_you','About You'],['household','Your Household'],['family_members','Family Members'],['food_needs','Food Needs'],['kitchen','Your Kitchen'],['appliances_tools','Appliances & Tools'],['inventory','Food Inventory'],['meal_matching','Start Meal Matching']];
/* Profile question bank (04_profiling.sql + 06_age_rules.sql) */
const QUESTIONS=[
 {c:'likes',tab:'Likes',p:'What does {name} enjoy eating?',h:'Liked foods move up in suggestions.',opt:'cats',eff:'like'},
 {c:'dislikes',tab:'Dislikes',p:'What does {name} not like?',h:'Disliked foods get a warning, not a block.',opt:'cats',eff:'dislike'},
 {c:'allergies',tab:'Allergies',p:'Does {name} have any food allergies?',alert:'Allergy: {name} must avoid these foods. This is different from a preference.',opt:'allergens',eff:'allergy'},
 {c:'intolerances',tab:'Intolerances',p:'Does {name} have any food intolerances?',h:'Foods that upset {name}, but are not allergies.',opt:'intol',eff:'intolerance'},
 {c:'diet',tab:'Diet',p:'Does {name} follow any special diet?',opt:'diets',eff:'diet'},
 {c:'health_food',tab:'Health',p:'Does {name} need any special food requirements?',h:'Optional. Add only what applies. Starter guidance, not medical advice.',opt:'health',eff:'health',consent:true},
 {c:'not_yet_introduced',tab:'Not yet',p:'Are there foods you are not giving {name} yet?',h:'Your choice as a caregiver. Add what you are waiting on.',opt:'young',eff:'avoid',min:0,max:3},
 {c:'avoid_foods',tab:'Avoid',p:'Are there foods {name} should avoid?',h:'Your own choices, separate from allergies.',opt:'cats',eff:'avoid'},
 {c:'prioritize_foods',tab:'More of',p:'Are there foods {name} should eat more of?',opt:'cats',eff:'prioritize'}];
const LOC_TYPES={pantry:['Pantry','ambient'],refrigerator:['Refrigerator','chilled'],freezer:['Freezer','frozen'],cabinet:['Cabinets','ambient'],drawer:['Drawers','ambient'],kitchen_island:['Kitchen Island','ambient'],countertop:['Countertop','ambient'],spice_rack:['Spice Rack','ambient'],garage_refrigerator:['Garage Fridge','chilled'],garage_freezer:['Garage Freezer','frozen'],other:['Other','ambient']};
const UNITS={g:['mass',1,'g'],kg:['mass',1000,'kg'],oz:['mass',28.349523125,'oz'],lb:['mass',453.59237,'lb'],ml:['volume',1,'ml'],l:['volume',1000,'L'],fl_oz:['volume',29.5735295625,'fl oz'],cup:['volume',236.5882365,'cup'],tbsp:['volume',14.78676478125,'tbsp'],tsp:['volume',4.92892159375,'tsp'],pint:['volume',473.176473,'pt'],quart:['volume',946.352946,'qt'],gallon:['volume',3785.411784,'gal'],each:['count',1,'each']};
const UNIT_SETS={us:{mass:['oz','lb','g','kg'],volume:['fl_oz','cup','tbsp','tsp','pint','quart','gallon','ml','l'],count:['each']},metric:{mass:['g','kg'],volume:['ml','l','tbsp','tsp','cup'],count:['each']}};
const COUNTRIES={US:['United States','us','en','America/New_York'],BR:['Brazil','metric','pt','America/Sao_Paulo'],DE:['Germany','metric','de','Europe/Berlin'],PH:['Philippines','metric','en','Asia/Manila'],MX:['Mexico','metric','es','America/Mexico_City'],ES:['Spain','metric','es','Europe/Madrid'],PT:['Portugal','metric','pt','Europe/Lisbon'],FR:['France','metric','fr','Europe/Paris'],IT:['Italy','metric','it','Europe/Rome'],GB:['United Kingdom','metric','en','Europe/London'],CA:['Canada','metric','en','America/Toronto'],AU:['Australia','metric','en','Australia/Sydney'],AR:['Argentina','metric','es','America/Argentina/Buenos_Aires'],CO:['Colombia','metric','es','America/Bogota'],CL:['Chile','metric','es','America/Santiago'],PE:['Peru','metric','es','America/Lima'],AT:['Austria','metric','de','Europe/Vienna'],CH:['Switzerland','metric','de','Europe/Zurich'],NL:['Netherlands','metric','en','Europe/Amsterdam'],BE:['Belgium','metric','fr','Europe/Brussels'],IN:['India','metric','en','Asia/Kolkata'],JP:['Japan','metric','en','Asia/Tokyo']};
const US_STATES='Alabama,Alaska,Arizona,Arkansas,California,Colorado,Connecticut,Delaware,District of Columbia,Florida,Georgia,Hawaii,Idaho,Illinois,Indiana,Iowa,Kansas,Kentucky,Louisiana,Maine,Maryland,Massachusetts,Michigan,Minnesota,Mississippi,Missouri,Montana,Nebraska,Nevada,New Hampshire,New Jersey,New Mexico,New York,North Carolina,North Dakota,Ohio,Oklahoma,Oregon,Pennsylvania,Rhode Island,South Carolina,South Dakota,Tennessee,Texas,Utah,Vermont,Virginia,Washington,West Virginia,Wisconsin,Wyoming'.split(',');
/* Food items: id:[name,cat,[usUnit,metricUnit],loc,shelfLifeDays,allergens,aliases] */
const F={
eggs:['Eggs','eggs',['each','each'],'refrigerator',28,['egg'],'ovos ovo huevos huevo eier ei oeufs itlog'],
milk:['Whole milk','dairy',['gallon','l'],'refrigerator',7,['milk','lactose'],'leite leche milch lait gatas'],
cheddar:['Cheddar cheese','dairy',['oz','g'],'refrigerator',30,['milk','lactose'],'queijo queso kase cheese keso'],
mozzarella:['Mozzarella','dairy',['oz','g'],'refrigerator',14,['milk','lactose'],'mucarela mussarela'],
parmesan:['Parmesan','dairy',['oz','g'],'refrigerator',60,['milk'],'parmesao parmesano parmigiano'],
butter:['Butter','dairy',['lb','g'],'refrigerator',60,['milk'],'manteiga mantequilla mantikilya'],
yogurt:['Yogurt','dairy',['oz','g'],'refrigerator',14,['milk','lactose'],'iogurte yogur joghurt'],
cream:['Heavy cream','dairy',['fl_oz','ml'],'refrigerator',10,['milk','lactose'],'creme de leite nata sahne'],
chicken:['Chicken breast','poultry',['lb','g'],'refrigerator',3,[],'frango peito de frango pollo pechuga hahnchen hahnchenbrust manok'],
beef:['Ground beef','meat',['lb','g'],'refrigerator',2,[],'carne moida carne picada hackfleisch giniling'],
pork:['Pork chops','meat',['lb','g'],'refrigerator',3,[],'lombo de porco cerdo schwein baboy'],
ham:['Ham','meat',['oz','g'],'refrigerator',5,[],'presunto jamon schinken hamon'],
sausage:['Sausages','meat',['lb','g'],'refrigerator',7,[],'linguica salchicha wurst wurstchen longganisa'],
salmon:['Salmon','seafood',['lb','g'],'refrigerator',2,['fish'],'salmao salmon lachs'],
tuna:['Canned tuna','seafood',['oz','g'],'pantry',730,['fish'],'atum atun thunfisch'],
shrimp:['Shrimp','seafood',['lb','g'],'freezer',90,['shellfish'],'camarao camarones gambas garnelen hipon'],
tofu:['Tofu','legumes',['oz','g'],'refrigerator',7,['soy'],'tokwa'],
blackbeans:['Black beans','legumes',['oz','g'],'pantry',365,[],'feijao preto feijao frijoles negros schwarze bohnen'],
lentils:['Lentils','legumes',['oz','g'],'pantry',365,[],'lentilha lentejas linsen'],
chickpeas:['Chickpeas','legumes',['oz','g'],'pantry',365,[],'grao de bico garbanzos kichererbsen'],
spinach:['Spinach','vegetables',['oz','g'],'refrigerator',5,[],'espinafre espinaca spinat'],
tomatoes:['Tomatoes','vegetables',['each','each'],'countertop',7,[],'tomate tomates tomaten kamatis'],
onion:['Onion','vegetables',['each','each'],'pantry',30,[],'cebola cebolla zwiebel sibuyas'],
garlic:['Garlic (cloves)','vegetables',['each','each'],'pantry',60,[],'alho ajo knoblauch bawang'],
carrots:['Carrots','vegetables',['each','each'],'refrigerator',21,[],'cenoura zanahoria karotte mohre karotten'],
potatoes:['Potatoes','vegetables',['lb','kg'],'pantry',30,[],'batata papa patata kartoffel kartoffeln patatas'],
bellpepper:['Bell pepper','vegetables',['each','each'],'refrigerator',10,[],'pimentao pimiento paprika'],
broccoli:['Broccoli','vegetables',['oz','g'],'refrigerator',7,[],'brocolis brocoli brokkoli'],
zucchini:['Zucchini','vegetables',['each','each'],'refrigerator',7,[],'abobrinha calabacin zucchini'],
lettuce:['Lettuce','vegetables',['each','each'],'refrigerator',7,[],'alface lechuga kopfsalat salat litsugas'],
cucumber:['Cucumber','vegetables',['each','each'],'refrigerator',7,[],'pepino gurke'],
ginger:['Ginger','vegetables',['oz','g'],'refrigerator',21,[],'gengibre jengibre ingwer luya'],
cilantro:['Cilantro (bunch)','vegetables',['each','each'],'refrigerator',7,[],'coentro koriander wansoy'],
corn:['Canned corn','vegetables',['oz','g'],'pantry',730,[],'milho maiz mais'],
bananas:['Bananas','fruits',['each','each'],'countertop',6,[],'banana platano banane saging'],
apples:['Apples','fruits',['each','each'],'refrigerator',30,[],'maca manzana apfel apfel mansanas'],
lemons:['Lemons / limes','fruits',['each','each'],'refrigerator',21,[],'limao limon zitrone kalamansi'],
berries:['Strawberries','fruits',['oz','g'],'refrigerator',5,[],'morango fresas erdbeeren'],
avocado:['Avocado','fruits',['each','each'],'countertop',5,[],'abacate aguacate'],
rice:['Rice','grains',['lb','kg'],'pantry',365,[],'arroz reis bigas kanin'],
pasta:['Pasta','grains',['lb','g'],'pantry',365,['wheat','gluten'],'macarrao massa espaguete fideos nudeln spaghetti'],
ricenoodles:['Rice noodles','grains',['oz','g'],'pantry',365,[],'bifum fideos de arroz reisnudeln bihon'],
bread:['Bread (slices)','grains',['each','each'],'countertop',5,['wheat','gluten'],'pao pan brot tinapay'],
flour:['Flour','grains',['lb','kg'],'pantry',240,['wheat','gluten'],'farinha harina mehl harina'],
oats:['Rolled oats','grains',['oz','g'],'pantry',365,['gluten'],'aveia avena haferflocken'],
tortillas:['Tortillas','grains',['each','each'],'pantry',14,['wheat','gluten'],''],
oliveoil:['Olive oil','oils_fats',['fl_oz','ml'],'pantry',365,[],'azeite aceite de oliva olivenol'],
sesameoil:['Sesame oil','oils_fats',['fl_oz','ml'],'pantry',365,['sesame'],'oleo de gergelim aceite de sesamo sesamol'],
peanutbutter:['Peanut butter','pantry',['oz','g'],'pantry',180,['peanuts'],'pasta de amendoim mantequilla de mani erdnussbutter'],
soysauce:['Soy sauce','pantry',['fl_oz','ml'],'pantry',365,['soy','wheat','gluten'],'shoyu molho de soja salsa de soja sojasosse toyo'],
tomatosauce:['Tomato sauce','pantry',['oz','g'],'pantry',365,[],'molho de tomate salsa de tomate tomatensosse'],
broth:['Vegetable broth','pantry',['fl_oz','ml'],'pantry',365,[],'caldo de legumes caldo bruhe'],
sugar:['Sugar','pantry',['lb','kg'],'pantry',730,[],'acucar azucar zucker asukal'],
honey:['Honey','pantry',['oz','g'],'pantry',730,[],'mel miel honig pulot'],
salt:['Salt','spices',['oz','g'],'spice_rack',1825,[],'sal salz asin'],
pepper:['Black pepper','spices',['oz','g'],'spice_rack',730,[],'pimenta do reino pimienta pfeffer paminta'],
almonds:['Almonds','snacks',['oz','g'],'pantry',180,['tree_nuts'],'amendoas almendras mandeln'],
peanuts:['Peanuts','snacks',['oz','g'],'pantry',180,['peanuts'],'amendoim mani cacahuetes erdnusse mani'],
crackers:['Crackers','snacks',['oz','g'],'pantry',120,['wheat','gluten'],'bolacha galletas kekse'],
orangejuice:['Orange juice','beverages',['fl_oz','l'],'refrigerator',7,[],'suco de laranja jugo de naranja orangensaft'],
coffee:['Coffee','beverages',['oz','g'],'pantry',180,[],'cafe kaffee kape'],
frozenpeas:['Frozen peas','frozen',['oz','g'],'freezer',240,[],'ervilha congelada guisantes tiefkuhlerbsen'],
icecream:['Ice cream','frozen',['fl_oz','l'],'freezer',60,['milk','lactose'],'sorvete helado eis sorbetes']};
const FOODS={};for(const id in F){const x=F[id];FOODS[id]={id,name:x[0],cat:x[1],u:{us:x[2][0],metric:x[2][1]},loc:x[3],life:x[4],al:x[5],alias:x[6]};}
const PKG={US:{eggs:[[12,'each','1 dozen'],[18,'each','18-pack']],milk:[[1,'gallon','1 gallon jug'],[0.5,'gallon','half gallon']],pasta:[[1,'lb','1 lb box']],rice:[[2,'lb','2 lb bag'],[5,'lb','5 lb bag']],butter:[[1,'lb','1 lb (4 sticks)']],cheddar:[[8,'oz','8 oz block']],blackbeans:[[15,'oz','15 oz can']],chickpeas:[[15,'oz','15 oz can']],tuna:[[5,'oz','5 oz can']]},
 DE:{eggs:[[10,'each','10-pack'],[6,'each','6-pack']],milk:[[1,'l','1 liter carton']],pasta:[[500,'g','500 g pack']],rice:[[1,'kg','1 kg bag']],butter:[[250,'g','250 g block']]},
 BR:{eggs:[[12,'each','1 dozen'],[30,'each','30-tray']],milk:[[1,'l','1 liter carton']],pasta:[[500,'g','500 g pack']],rice:[[5,'kg','5 kg bag'],[1,'kg','1 kg bag']],blackbeans:[[1,'kg','1 kg bag']]},
 PH:{eggs:[[12,'each','1 dozen'],[30,'each','1 tray']],rice:[[5,'kg','5 kg bag'],[25,'kg','25 kg sack']],soysauce:[[1000,'ml','1 L bottle']]}};
/* Kitchen item catalog (09_kitchen_catalog_seed.sql). Tabs → groups → [code,name,useTag,regions] */
const KCAT=[
 ['appliances','Appliances',[['Refrigeration',[['refrigerator','Refrigerator','Keeps food fresh'],['freezer','Freezer','Keeps food fresh'],['wine_fridge','Wine Fridge','Wine']]],
  ['Cooking appliances',[['range','Range / Stove','Cooking'],['cooktop','Cooktop','Cooking'],['oven','Oven','Baking'],['microwave','Microwave','Reheating']]],
  ['Small appliances',[['air_fryer','Air Fryer','Cooking'],['slow_cooker','Slow Cooker','Cooking'],['pressure_cooker','Pressure Cooker','Cooking'],['rice_cooker','Rice Cooker','Cooking'],['toaster','Toaster','Cooking'],['toaster_oven','Toaster Oven','Baking'],['blender','Blender','Prep'],['food_processor','Food Processor','Prep'],['stand_mixer','Stand Mixer','Prep'],['immersion_blender','Immersion Blender','Prep'],['waffle_maker','Waffle Maker','Cooking'],['raclette_grill','Raclette Grill','Cooking','DE,FR,CH,AT,NL,BE']]],
  ['Beverage',[['coffee_maker','Coffee Maker','Beverages'],['espresso_machine','Espresso Machine','Beverages'],['electric_kettle','Electric Kettle','Beverages'],['moka_pot','Moka Pot','Beverages','IT,ES,PT,FR,AR,UY,BR,CL,CO']]],
  ['Dishwashing',[['dishwasher','Dishwasher','Cleaning']]]]],
 ['cookware','Cookware',[['Pots & pans',[['frying_pan','Frying Pan','Cooking'],['nonstick_pan','Nonstick Pan','Cooking'],['cast_iron_skillet','Cast Iron Skillet','Cooking'],['saute_pan','Sauté Pan','Cooking'],['saucepan','Saucepan','Cooking'],['stockpot','Stockpot','Cooking'],['dutch_oven','Dutch Oven','Cooking'],['wok','Wok','Cooking'],['steamer_pot','Steamer','Cooking']]],
  ['Specialty',[['cazuela','Clay Pot (Cazuela)','Cooking','ES,PT,MX,AR,CL,CO,PE'],['comal','Comal / Griddle','Cooking','MX,GT,SV,HN,CO,VE,US'],['paella_pan','Paella Pan','Cooking','ES,AR,UY,CL,PT,FR,IT'],['crepe_pan','Crêpe Pan','Cooking','FR,BE,DE,CH,BR'],['fondue_set','Fondue Set','Cooking','CH,FR,DE,AT,IT'],['tortilla_press','Tortilla Press','Prep','MX,US,GT']]],
  ['Bakeware',[['baking_sheet','Baking Sheet','Baking'],['cake_pan','Cake Pan','Baking'],['loaf_pan','Loaf Pan','Baking'],['muffin_tin','Muffin Tin','Baking'],['casserole_dish','Casserole Dish','Baking'],['roasting_pan','Roasting Pan','Baking'],['pizza_stone','Pizza Stone','Baking']]]]],
 ['utensils','Utensils',[['Knives & cutting',[['chef_knife','Chef Knife','Prep'],['paring_knife','Paring Knife','Prep'],['bread_knife','Bread Knife','Prep'],['cutting_board','Cutting Board','Prep'],['kitchen_shears','Kitchen Shears','Prep']]],
  ['Measuring',[['measuring_cups','Measuring Cups','Measuring'],['measuring_spoons','Measuring Spoons','Measuring'],['kitchen_scale','Kitchen Scale','Measuring'],['meat_thermometer','Meat Thermometer','Safety']]],
  ['Mixing & prep',[['mixing_bowl','Mixing Bowl','Prep'],['whisk','Whisk','Prep'],['colander','Colander','Prep'],['grater','Grater','Prep'],['peeler','Peeler','Prep'],['rolling_pin','Rolling Pin','Baking'],['mortar_pestle','Mortar & Pestle','Prep']]],
  ['Handheld tools',[['spatula','Spatula','Cooking'],['wooden_spoon','Wooden Spoon','Cooking'],['ladle','Ladle','Serving'],['tongs','Tongs','Cooking'],['can_opener','Can Opener','Prep'],['corkscrew','Corkscrew','Wine']]]]],
 ['dinnerware','Dinnerware',[['Plates',[['dinner_plate','Dinner Plate','Dining'],['salad_plate','Salad / Lunch Plate','Dining'],['dessert_plate','Dessert Plate','Dining']]],['Bowls',[['soup_bowl','Soup Bowl','Dining'],['cereal_bowl','Cereal Bowl','Dining'],['rice_bowl','Rice Bowl','Dining']]],['Cups & mugs',[['mug','Mug','Hot drinks'],['teacup_saucer','Teacup & Saucer','Hot drinks'],['espresso_cup','Espresso Cup','Hot drinks'],['mate_gourd','Mate Gourd','Hot drinks','AR,UY,PY,BR,CL']]],['Cutlery',[['dinner_fork','Dinner Fork','Dining'],['dinner_knife','Dinner Knife','Dining'],['teaspoon','Teaspoon','Dining'],['soup_spoon','Soup Spoon','Dining'],['chopsticks','Chopsticks','Dining']]]]],
 ['glassware','Glassware',[['Wine glasses',[['red_wine_glass','Red wine glass','Wine'],['white_wine_glass','White wine glass','Wine'],['champagne_flute','Champagne flute','Sparkling']]],
  ['Tumblers & water glasses',[['water_tumbler','Water tumbler','Water'],['juice_glass','Juice glass','Water'],['highball_glass','Highball glass','Cocktails'],['rocks_glass','Rocks glass','Spirits']]],
  ['Beer glassware',[['pint_glass','Pint glass','Beer'],['pilsner_glass','Pilsner glass','Beer'],['beer_mug_stein','Beer mug / stein','Beer'],['weizen_glass','Wheat beer glass','Beer','DE,AT']]],
  ['Pitchers & decanters',[['water_pitcher','Water pitcher','Serving'],['wine_decanter','Wine decanter','Serving · Wine'],['carafe','Carafe','Serving']]]]],
 ['storage','Storage',[['Containers',[['storage_container','Food Storage Container','Storage'],['glass_container','Glass Food Container','Storage'],['lunch_box','Lunch Box','Storage']]],['Jars & bags',[['mason_jar','Mason Jar','Storage'],['canister','Canister','Storage'],['spice_jar','Spice Jar','Storage'],['freezer_bags','Freezer Bags','Keeps food fresh']]]]],
 ['serveware','Serveware',[['Serving',[['serving_platter','Serving Platter','Serving'],['serving_bowl','Serving Bowl','Serving'],['teapot','Teapot','Hot drinks'],['salt_pepper_shakers','Salt & Pepper Shakers','Dining'],['trivet','Trivet','Serving']]]]]];
const COUNTRY_ADJ={DE:'Germany',AT:'Austria',BR:'Brazil',ES:'Spain',MX:'Mexico',IT:'Italy',FR:'France',CH:'Switzerland',AR:'Argentina',PT:'Portugal',US:'the US',CO:'Colombia',CL:'Chile',PE:'Peru',BE:'Belgium',NL:'the Netherlands',UY:'Uruguay',PY:'Paraguay',GT:'Guatemala'};
/* Recipes: [id,title,servings,mins,ingredients[[food,qty,unit,optional]],appliances[],nutrients/serving{cal,protein,sat,sugar,fiber,sodium},steps] */
const R=[
 ['veg_pasta','Creamy Veggie Pasta',4,25,[['pasta',250,'g'],['spinach',100,'g'],['tomatoes',2,'each'],['cream',200,'ml'],['parmesan',40,'g'],['garlic',2,'each'],['oliveoil',15,'ml']],['range'],{cal:520,protein:18,sat:9,sugar:6,fiber:5,sodium:520},['Boil the pasta in salted water until al dente.','Sauté garlic in olive oil, add chopped tomatoes and spinach until wilted.','Stir in cream and parmesan, then toss with the drained pasta.']],
 ['peanut_noodles','Peanut Noodles',4,20,[['ricenoodles',200,'g'],['peanutbutter',60,'g'],['soysauce',30,'ml'],['carrots',2,'each'],['cucumber',1,'each'],['lemons',1,'each'],['garlic',1,'each']],['range'],{cal:450,protein:16,sat:4,sugar:8,fiber:4,sodium:780},['Soak or boil the rice noodles; drain and rinse.','Whisk peanut butter, soy sauce, lime juice, grated garlic and warm water.','Toss noodles with sauce, shredded carrot and cucumber.']],
 ['oven_eggs','Oven Baked Eggs',3,20,[['eggs',6,'each'],['spinach',60,'g'],['tomatoes',2,'each'],['cheddar',50,'g'],['oliveoil',10,'ml']],['oven'],{cal:310,protein:19,sat:8,sugar:3,fiber:2,sodium:420},['Heat the oven to 190 °C / 375 °F.','Layer spinach and tomato in an oiled dish, crack in the eggs.','Top with cheese and bake 12–15 minutes.']],
 ['salmon_bowl','Salmon Rice Bowl',4,30,[['salmon',400,'g'],['rice',200,'g'],['cucumber',1,'each'],['avocado',1,'each'],['soysauce',20,'ml'],['sesameoil',5,'ml',1]],['range'],{cal:540,protein:31,sat:5,sugar:2,fiber:4,sodium:610},['Cook the rice.','Pan-sear the salmon 4 minutes per side.','Serve over rice with sliced cucumber, avocado and soy sauce.']],
 ['chicken_stirfry','Chicken Stir-Fry',4,25,[['chicken',500,'g'],['bellpepper',2,'each'],['broccoli',300,'g'],['soysauce',30,'ml'],['garlic',2,'each'],['ginger',15,'g'],['rice',250,'g'],['oliveoil',15,'ml']],['range'],{cal:480,protein:36,sat:2,sugar:5,fiber:4,sodium:690},['Cook the rice.','Stir-fry sliced chicken until golden; remove.','Stir-fry vegetables with garlic and ginger, return chicken, add soy sauce.']],
 ['bean_tacos','Black Bean Tacos',4,20,[['tortillas',8,'each'],['blackbeans',400,'g'],['tomatoes',2,'each'],['onion',1,'each'],['avocado',1,'each'],['cilantro',1,'each',1],['cheddar',60,'g',1],['lemons',1,'each']],['range'],{cal:430,protein:15,sat:4,sugar:4,fiber:12,sodium:480},['Warm the beans with diced onion and a pinch of salt.','Warm tortillas in a dry pan.','Fill with beans, tomato, avocado, cilantro and a squeeze of lime.']],
 ['lentil_soup','Lentil Soup',6,40,[['lentils',250,'g'],['carrots',2,'each'],['onion',1,'each'],['garlic',2,'each'],['tomatoes',2,'each'],['broth',1000,'ml'],['oliveoil',15,'ml']],['range'],{cal:260,protein:14,sat:1,sugar:6,fiber:11,sodium:450},['Sauté onion, carrot and garlic in olive oil.','Add lentils, tomatoes and broth; simmer 25–30 minutes.','Season and serve.']],
 ['spanish_omelette','Spanish Omelette',4,35,[['eggs',6,'each'],['potatoes',500,'g'],['onion',1,'each'],['oliveoil',60,'ml'],['salt',3,'g']],['range'],{cal:360,protein:14,sat:4,sugar:3,fiber:3,sodium:390},['Slowly fry thin potato and onion slices in olive oil until soft.','Mix with beaten eggs and salt.','Cook in a pan until set, flip with a plate and finish.']],
 ['rice_beans','Arroz com Feijão',6,45,[['rice',300,'g'],['blackbeans',400,'g'],['onion',1,'each'],['garlic',3,'each'],['oliveoil',15,'ml'],['salt',4,'g']],['range'],{cal:390,protein:13,sat:1,sugar:1,fiber:9,sodium:350},['Sauté garlic and onion, add rice, toast 1 minute, add water and cook.','Heat the beans with a little garlic and salt.','Serve together.']],
 ['overnight_oats','Overnight Oats',2,5,[['oats',160,'g'],['milk',400,'ml'],['yogurt',150,'g'],['honey',20,'g',1],['berries',150,'g']],[],{cal:380,protein:16,sat:3,sugar:18,fiber:7,sodium:110},['Mix oats, milk and yogurt in a jar.','Refrigerate overnight.','Top with berries and honey.']],
 ['banana_pancakes','Banana Pancakes',4,25,[['flour',200,'g'],['eggs',2,'each'],['milk',300,'ml'],['bananas',2,'each'],['butter',20,'g'],['sugar',20,'g',1]],['range'],{cal:340,protein:10,sat:5,sugar:14,fiber:3,sodium:260},['Mash bananas, whisk in eggs and milk.','Fold in flour and sugar.','Cook ladlefuls in a buttered pan until golden on both sides.']],
 ['chicken_adobo','Chicken Adobo',5,50,[['chicken',600,'g'],['soysauce',60,'ml'],['garlic',6,'each'],['onion',1,'each'],['pepper',2,'g'],['rice',300,'g']],['range'],{cal:470,protein:34,sat:3,sugar:2,fiber:1,sodium:980},['Marinate chicken with soy sauce, garlic and pepper.','Brown the chicken, add marinade, onion and a cup of water.','Simmer 30 minutes; serve with rice.']],
 ['roast_chicken','Roast Chicken & Potatoes',5,60,[['chicken',700,'g'],['potatoes',800,'g'],['carrots',3,'each'],['oliveoil',30,'ml'],['garlic',4,'each'],['lemons',1,'each']],['oven'],{cal:520,protein:38,sat:3,sugar:4,fiber:5,sodium:420},['Heat the oven to 200 °C / 400 °F.','Toss chicken, potatoes, carrots, garlic and lemon with oil and salt.','Roast 45 minutes, turning once.']],
 ['tuna_salad','Tuna Salad',3,10,[['tuna',300,'g'],['lettuce',1,'each'],['tomatoes',2,'each'],['cucumber',1,'each'],['oliveoil',30,'ml'],['lemons',1,'each'],['eggs',2,'each',1]],[],{cal:290,protein:27,sat:3,sugar:4,fiber:3,sodium:520},['Chop the lettuce, tomato and cucumber.','Add flaked tuna.','Dress with olive oil and lemon.']],
 ['garlic_shrimp','Garlic Shrimp Rice',4,25,[['shrimp',400,'g'],['rice',250,'g'],['garlic',5,'each'],['butter',30,'g'],['lemons',1,'each']],['range'],{cal:430,protein:27,sat:5,sugar:1,fiber:1,sodium:640},['Cook the rice.','Sauté garlic in butter, add shrimp and cook until pink.','Finish with lemon and serve over rice.']],
 ['bolognese','Beef Bolognese',5,45,[['pasta',400,'g'],['beef',500,'g'],['tomatosauce',500,'g'],['onion',1,'each'],['carrots',1,'each'],['garlic',2,'each'],['parmesan',30,'g',1]],['range'],{cal:610,protein:33,sat:8,sugar:9,fiber:6,sodium:720},['Brown the beef with onion, carrot and garlic.','Add tomato sauce and simmer 25 minutes.','Serve over pasta with parmesan.']],
 ['chickpea_curry','Chickpea Curry',4,35,[['chickpeas',400,'g'],['tomatoes',3,'each'],['onion',1,'each'],['garlic',3,'each'],['ginger',15,'g'],['spinach',100,'g'],['rice',250,'g'],['oliveoil',15,'ml']],['range'],{cal:450,protein:15,sat:2,sugar:7,fiber:11,sodium:410},['Cook the rice.','Sauté onion, garlic and ginger; add tomatoes and chickpeas.','Simmer 15 minutes, stir in spinach.']],
 ['tofu_stirfry','Tofu Veggie Stir-Fry',4,25,[['tofu',400,'g'],['broccoli',250,'g'],['bellpepper',1,'each'],['soysauce',30,'ml'],['sesameoil',10,'ml'],['ricenoodles',200,'g']],['range'],{cal:400,protein:21,sat:2,sugar:5,fiber:5,sodium:700},['Prepare the noodles.','Crisp cubed tofu in a hot pan.','Add vegetables, sauce and noodles; toss.']],
 ['airfryer_tenders','Air-Fryer Chicken Tenders',4,25,[['chicken',500,'g'],['flour',60,'g'],['eggs',1,'each'],['salt',3,'g']],['air_fryer'],{cal:330,protein:35,sat:2,sugar:1,fiber:1,sodium:480},['Cut chicken into strips; dip in egg then seasoned flour.','Air-fry at 200 °C / 400 °F for 10–12 minutes, turning once.']],
 ['berry_smoothie','Banana Berry Smoothie',2,5,[['bananas',2,'each'],['berries',150,'g'],['yogurt',200,'g'],['milk',200,'ml']],['blender'],{cal:260,protein:11,sat:3,sugar:30,fiber:5,sodium:120},['Blend everything until smooth.']],
 ['ham_toastie','Ham & Cheese Toastie',2,10,[['bread',4,'each'],['ham',100,'g'],['cheddar',60,'g'],['butter',20,'g']],['range'],{cal:470,protein:24,sat:13,sugar:3,fiber:2,sodium:1250},['Butter the outsides of the bread.','Fill with ham and cheese.','Toast in a pan until golden and melted.']],
 ['veggie_frittata','Zucchini Frittata',4,25,[['eggs',6,'each'],['zucchini',1,'each'],['onion',1,'each'],['parmesan',30,'g'],['oliveoil',15,'ml']],['range'],{cal:240,protein:16,sat:5,sugar:3,fiber:1,sodium:330},['Sauté sliced zucchini and onion.','Pour over beaten eggs with parmesan.','Cook covered on low heat until set.']]];
const RECIPES=R.map(x=>({id:x[0],title:x[1],serv:x[2],mins:x[3],ing:x[4].map(i=>({f:i[0],q:i[1],u:i[2],opt:!!i[3]})),app:x[5],n:x[6],steps:x[7]}));
return {CATS,LEAF_CATS,ALLERGENS,INTOL,DIETS,DIET_EX,HEALTH,NUTR,AGE_BANDS,RELS,ROLES,GOALS,STEPS,QUESTIONS,LOC_TYPES,UNITS,UNIT_SETS,COUNTRIES,US_STATES,FOODS,PKG,KCAT,COUNTRY_ADJ,RECIPES};
});
