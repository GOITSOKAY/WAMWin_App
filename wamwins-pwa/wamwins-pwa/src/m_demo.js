/* Sample household (matches the design mockups): The Silva Family across New York, São Paulo and München */
W.def('demo', function(W){
const E=W.use('engine');
return {load:async function(){const st=W.blank(),id=()=>W.uid(),t=Date.now(),d=n=>E.iso(E.addDays(E.today(),n));
 const salt=id();st.account={first:'Maria',last:'Smith',email:'maria@email.com',salt,pw:await W.hashPw('wamwins123',salt),verified:true,created:t};st.signedIn=true;
 st.consent={privacy:t,health:true,log:[{type:'privacy_notice',value:true,at:t},{type:'health_data',value:true,at:t}]};
 st.about={name:'Maria',role:'parent',goals:['decide_what_to_cook','manage_inventory']};
 st.household={id:id(),name:'The Silva Family',people:5,country:'US',region:'New York',created:t};
 const ny={id:id(),name:'New York',country:'US',region:'New York',units:'us',locale:'en',tz:'America/New_York'},sp={id:id(),name:'São Paulo',country:'BR',region:'São Paulo',units:'metric',locale:'pt',tz:'America/Sao_Paulo'},mu={id:id(),name:'München',country:'DE',region:'Bayern',units:'metric',locale:'de',tz:'Europe/Berlin'};
 st.kitchens=[ny,sp,mu];st.active=sp.id;
 const all=['likes','dislikes','allergies','intolerances','diet','health_food','avoid_foods','prioritize_foods'];const full=o=>Object.fromEntries(all.map(c=>[c,o[c]||['none']]));
 st.members=[{id:id(),self:true,name:'Maria',rel:'self',band:'age_18_64',age:'',k:ny.id,answers:full({likes:['vegetables','seafood'],health_food:['low_sodium']})},
  {id:id(),name:'Carlos',rel:'spouse_partner',band:'age_18_64',age:'',k:ny.id,answers:{likes:['meat','grains'],dislikes:['seafood'],allergies:['none']}},
  {id:id(),name:'Sofia',rel:'child',band:'age_6_12',age:10,k:ny.id,answers:{}},
  {id:id(),name:'Ana',rel:'child',band:'age_6_12',age:8,k:sp.id,answers:{likes:['fruits','grains'],dislikes:['spices'],allergies:['peanuts']}},
  {id:id(),name:'Lukas',rel:'child',band:'age_6_12',age:6,k:mu.id,answers:{intolerances:['lactose']}}];
 const L=(k,type,name,parent)=>{const l={id:id(),k:k.id,type,name,parent};st.locations.push(l);return l;};
 const loc={};for(const k of st.kitchens){const p=L(k,'pantry','Pantry');loc[k.id]={pantry:p,s1:L(k,'shelf','Shelf 1',p.id),s2:L(k,'shelf','Shelf 2',p.id),fr:L(k,'refrigerator','Refrigerator'),fz:L(k,'freezer','Freezer'),ct:L(k,'countertop','Countertop'),sr:L(k,'spice_rack','Spice Rack')};}
 st.kitems[ny.id]={refrigerator:1,freezer:1,range:1,oven:1,microwave:1,air_fryer:1,toaster:1,coffee_maker:1,dishwasher:1,blender:1,frying_pan:2,saucepan:2,stockpot:1,baking_sheet:2,chef_knife:1,cutting_board:2,dinner_plate:8,water_tumbler:8};
 st.kitems[sp.id]={refrigerator:1,freezer:1,range:1,microwave:1,blender:1,rice_cooker:1,pressure_cooker:1,moka_pot:1,frying_pan:2,saucepan:2,stockpot:1,chef_knife:1,cutting_board:1,dinner_plate:6};
 st.kitems[mu.id]={refrigerator:1,freezer:1,range:1,oven:1,microwave:1,electric_kettle:1,coffee_maker:1,frying_pan:1,saucepan:2,red_wine_glass:6,white_wine_glass:6,champagne_flute:4,water_tumbler:10,pint_glass:4,weizen_glass:6,wine_decanter:1};
 st.ui.kdone={};for(const k of st.kitchens)st.ui.kdone[k.id]=['appliances','cookware','utensils','dinnerware','glassware','storage','serveware'];
 const add=(k,food,qty,unit,where,o)=>{const lot=Object.assign({id:id(),k:k.id,food,qty,init:qty,unit,loc:loc[k.id][where].id,added:t-864e5*3},o||{});if(lot.init0){lot.init=lot.init0;delete lot.init0;}st.inv.push(lot);E.tx(lot,'add',E.toBase(qty,unit));};
 /* São Paulo */
 add(sp,'eggs',12,'each','fr',{brand:'Granja',pkg:'1 dozen',packs:1});add(sp,'milk',1,'l','fr',{exp:d(2)});add(sp,'pasta',500,'g','s1');add(sp,'spinach',200,'g','fr',{bestBy:d(3)});add(sp,'tomatoes',6,'each','ct');add(sp,'cream',300,'ml','fr',{exp:d(9)});add(sp,'parmesan',150,'g','fr');add(sp,'garlic',10,'each','s2');add(sp,'oliveoil',500,'ml','s2');
 add(sp,'peanutbutter',350,'g','s1');add(sp,'ricenoodles',400,'g','s1');add(sp,'rice',5,'kg','s1');add(sp,'blackbeans',1,'kg','s1');add(sp,'onion',2,'each','s2',{init0:8});add(sp,'bananas',6,'each','ct',{bestBy:d(1)});add(sp,'carrots',4,'each','fr');add(sp,'cucumber',2,'each','fr');add(sp,'lemons',5,'each','fr');add(sp,'soysauce',500,'ml','s2');add(sp,'chicken',600,'g','fz',{bestBy:d(40)});add(sp,'yogurt',400,'g','fr',{exp:d(3)});add(sp,'berries',250,'g','fr',{bestBy:d(2)});add(sp,'coffee',100,'g','s2',{init0:500});add(sp,'salt',500,'g','sr');add(sp,'avocado',2,'each','ct',{bestBy:d(2)});
 /* New York */
 add(ny,'eggs',18,'each','fr');add(ny,'milk',1,'gallon','fr',{exp:d(5)});add(ny,'cheddar',8,'oz','fr');add(ny,'butter',1,'lb','fr');add(ny,'chicken',2,'lb','fr',{exp:d(1)});add(ny,'potatoes',5,'lb','pantry');add(ny,'pasta',2,'lb','s1');add(ny,'tomatosauce',24,'oz','s1');add(ny,'beef',1,'lb','fr',{exp:d(2)});add(ny,'onion',3,'each','pantry');add(ny,'garlic',12,'each','pantry');add(ny,'carrots',6,'each','fr');add(ny,'oliveoil',16,'fl_oz','s2');add(ny,'lemons',3,'each','fr');add(ny,'flour',5,'lb','s1');add(ny,'bread',6,'each','ct',{init0:20,bestBy:d(2)});add(ny,'ham',8,'oz','fr');add(ny,'salmon',1,'lb','fz');add(ny,'rice',2,'lb','s1');
 /* München */
 add(mu,'eggs',10,'each','fr',{pkg:'10-pack',packs:1});add(mu,'milk',1,'l','fr',{exp:d(6)});add(mu,'potatoes',2,'kg','pantry');add(mu,'onion',4,'each','pantry');add(mu,'oliveoil',500,'ml','s2');add(mu,'zucchini',2,'each','fr');add(mu,'parmesan',100,'g','fr');add(mu,'bread',8,'each','ct');add(mu,'sausage',400,'g','fr',{exp:d(4)});
 st.ui.eaters={[sp.id]:st.members.filter(m=>m.name==='Ana'||m.name==='Lukas').map(m=>m.id)};
 st.shop=[{id:id(),k:sp.id,food:'tortillas',name:'Tortillas',note:'',done:false,at:t}];
 for(const s of ['about_you','household','family_members','food_needs','kitchen','appliances_tools','inventory','meal_matching'])st.setup[s]='done';
 st.setup.food_needs='skipped';
 W.S=st;W.save();}};});
