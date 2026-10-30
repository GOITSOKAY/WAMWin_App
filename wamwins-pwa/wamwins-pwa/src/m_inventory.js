/* Inventory: stock list, add/edit food (Step 7), use/waste ledger, shopping list */
W.def('inventory', function(W){
const R=W.use('ref'),E=W.use('engine'),e=W.e,S=()=>W.S;
W.addToShop=(k,food,name,note)=>{const st=S();const id=food||'';if(st.shop.some(s=>s.k===k&&!s.done&&(id?s.food===id:E.norm(s.name)===E.norm(name))))return false;st.shop.unshift({id:W.uid(),k,food:id,name:name||E.food(food).name,note:note||'',done:false,at:Date.now()});return true;};
const dotCls=l=>E.isExpired(l)?'x':E.isUseSoon(l)?'s':'';
const lotRow=l=>{const d=E.daysLeft(l);return '<div class="sw" data-id="'+l.id+'"><div class="swa"><button class="u" data-act="use" data-id="'+l.id+'">'+W.i('flame')+'Use</button><button class="d" data-act="del" data-id="'+l.id+'">'+W.i('trash')+'Delete</button></div><div class="swf"><button class="inv" data-act="lot" data-id="'+l.id+'"><span class="dot '+dotCls(l)+'"></span><span class="grow"><b style="display:block;font-weight:600">'+e(E.foodName(l))+'</b><span class="sub">'+e(E.locName(l.loc))+(l.brand?' · '+e(l.brand):'')+'</span></span><span style="text-align:right"><span class="q">'+e(E.fmt(l.qty,l.unit))+'</span><br>'+(d<=3?'<span class="pill'+(d<0?' al':'')+'">'+E.daysLabel(d)+'</span>':E.isLow(l)?'<span class="pill mu">Low</span>':'')+'</span></button></div></div>';};
W.screens.inventory={tab:'inventory',render(p){const st=S(),k=E.kitchen();if(!k)return '';const mode=st.ui.invMode||'stock';const flt=W.f.flt||p.flt||'all';const q=E.norm(W.f.q||'');
 const shopN=st.shop.filter(s=>s.k===k.id&&!s.done).length;
 let h='<div class="scr"><div class="scroll" style="padding-bottom:110px"><div class="row sp" style="margin-top:8px"><div><h1>Inventory</h1><p class="sub">'+e(k.name)+' kitchen · '+(k.units==='us'?'U.S.':'metric')+' units</p></div>'+W.logo(44)+'</div>'+W.kSwitch()+
  '<div class="seg" role="tablist"><button role="tab" class="'+(mode==='stock'?'on':'')+'" data-act="mode" data-m="stock">Stock</button><button role="tab" class="'+(mode==='shop'?'on':'')+'" data-act="mode" data-m="shop">Shopping list'+(shopN?' ('+shopN+')':'')+'</button></div>';
 if(mode==='stock'){const all=E.lots(k.id);let lots=all.filter(l=>!q||E.norm(E.foodName(l)).includes(q)||E.norm(E.food(l.food).alias).includes(q));
  const counts={all:all.length,soon:all.filter(l=>E.isUseSoon(l)&&!E.isExpired(l)).length,low:all.filter(E.isLow).length,exp:all.filter(E.isExpired).length};
  if(flt==='soon')lots=lots.filter(l=>E.isUseSoon(l)&&!E.isExpired(l));if(flt==='low')lots=lots.filter(E.isLow);if(flt==='exp')lots=lots.filter(E.isExpired);
  h+='<label class="search">'+W.i('search')+'<input data-f="q" type="search" placeholder="Search food" value="'+e(W.f.q||'')+'" aria-label="Search food"></label><div class="ksw">'+[['all','All'],['soon','Use soon'],['low','Low'],['exp','Expired']].map(x=>W.chip(x[1]+' '+counts[x[0]],flt===x[0],'data-act="flt" data-v="'+x[0]+'"','kc')).join('')+'</div>';
  if(!all.length)h+=W.empty('No food in this kitchen yet','Add what’s in your fridge and pantry. Local names work: “ovos” finds Eggs.','<button class="btn sm" data-act="add">'+W.i('plus')+'Add Food</button>');
  else if(!lots.length)h+=W.empty('Nothing here','Try another filter or search.','');
  else{const groups={};lots.sort((a,b)=>E.expiry(a)-E.expiry(b)).forEach(l=>{const n=E.locName(l.loc).split(' › ')[0];(groups[n]=groups[n]||[]).push(l);});
   h+=Object.keys(groups).sort().map(g=>'<div class="gl">'+e(g)+'</div><div class="list">'+groups[g].map(lotRow).join('')+'</div>').join('')+'<p class="sub" style="text-align:center">Swipe an item left to use or delete it.</p>';}
  h+='</div><button class="fab" data-act="add" aria-label="Add food">'+W.i('plus')+'</button></div>';}
 else{const items=st.shop.filter(s=>s.k===k.id);const lowS=E.lots(k.id).filter(E.isLow).filter(l=>!items.some(s=>!s.done&&s.food===l.food));
  h+='<div class="row"><label class="search grow">'+W.i('cart')+'<input data-f="si" placeholder="Add to list, e.g. leite" value="'+e(W.f.si||'')+'" aria-label="Add to shopping list" enterkeyhint="done"></label><button class="btn sm" data-act="sadd" style="min-height:48px">Add</button></div>';
  if(lowS.length)h+='<div class="card"><h3>Running low</h3><div class="wr mt8">'+lowS.slice(0,8).map(l=>W.chip('+ '+E.foodName(l),false,'data-act="slow" data-id="'+l.id+'"','kc')).join('')+'</div></div>';
  if(!items.length)h+=W.empty('Your list is empty','Add items here, from low-stock alerts, or from a recipe’s missing ingredients.','');
  else{const todo=items.filter(s=>!s.done),done=items.filter(s=>s.done);
   const row=s=>'<div class="sw" data-id="'+s.id+'" data-right="stog"><div class="swr">'+(s.done?'Undo':'Bought')+'</div><div class="swa" style="width:148px"><button class="d" data-act="sdel" data-id="'+s.id+'" style="flex:1">'+W.i('trash')+'Delete</button></div><div class="swf"><button class="inv" data-act="stog" data-id="'+s.id+'"><span class="num'+(s.done?' done':'')+'" style="width:30px;height:30px">'+(s.done?W.i('check'):'')+'</span><span class="grow" style="'+(s.done?'text-decoration:line-through;color:var(--t2)':'')+'"><b style="font-weight:600">'+e(s.name)+'</b>'+(s.note?'<br><span class="sub">'+e(s.note)+'</span>':'')+'</span></button></div></div>';
   h+='<div class="list">'+todo.map(row).join('')+'</div>'+(done.length?'<div class="gl">In the cart</div><div class="list">'+done.map(row).join('')+'</div><button class="btn y" data-act="stock">Add '+done.length+' bought item'+(done.length>1?'s':'')+' to inventory</button><button class="btn gh" data-act="sclear">Clear bought items</button>':'')+'<p class="sub" style="text-align:center">Swipe right to mark bought, left to delete.</p>';}
  h+='</div></div>';}
 return h;},
 onInput(k){if(k==='q')W.render();},
 mount(v){const i=v.querySelector('[data-f="si"]');if(i)i.addEventListener('keydown',ev=>{if(ev.key==='Enter'){ev.preventDefault();W.screens.inventory.acts.sadd();}});},
 acts:{mode:el=>{S().ui.invMode=el.dataset.m;W.save();W.render(true);},flt:el=>{W.f.flt=el.dataset.v;W.render();},add:()=>W.go('addfood',{}),
  lot:el=>lotSheet(el.dataset.id),use:el=>useSheet(el.dataset.id),
  del:el=>{const st=S();const l=st.inv.find(x=>x.id===el.dataset.id);if(!l)return;const i=st.inv.indexOf(l);st.inv.splice(i,1);E.tx(l,'delete',-E.toBase(l.qty,l.unit));W.save();W.render();W.toast(E.foodName(l)+' deleted',{action:'Undo',fn:()=>{st.inv.splice(i,0,l);st.tx.shift();W.save();W.render();}});},
  sadd:()=>{const t=String(W.f.si||'').trim();if(!t)return;const m=E.exact(t);const k=E.kitchen().id;if(!W.addToShop(k,m?m.id:'',m?m.name:t)){W.toast('Already on your list');return;}W.f.si='';W.save();W.render();W.toast((m?m.name:t)+' added to your list');},
  slow:el=>{const l=S().inv.find(x=>x.id===el.dataset.id);W.addToShop(l.k,l.food,E.foodName(l),'Running low');W.save();W.render();},
  stog:el=>{const s=S().shop.find(x=>x.id===el.dataset.id);if(!s)return;s.done=!s.done;W.save();W.render();},
  sdel:el=>{const st=S();const i=st.shop.findIndex(x=>x.id===el.dataset.id);const s=st.shop.splice(i,1)[0];W.save();W.render();W.toast(s.name+' removed',{action:'Undo',fn:()=>{st.shop.splice(i,0,s);W.save();W.render();}});},
  sclear:()=>{const k=E.kitchen().id;W.commit(s=>{s.shop=s.shop.filter(x=>!(x.k===k&&x.done));});},
  stock:()=>{const st=S(),k=E.kitchen();const done=st.shop.filter(s=>s.k===k.id&&s.done);let n=0;
   for(const s of done){if(s.food){const f=E.food(s.food);const pk=((R.PKG[k.country]||{})[f.id]||[])[0];const unit=pk?pk[1]:(f.u?f.u[k.units]:'each');const qty=pk?pk[0]:(E.unitDim(unit)==='count'?1:unit==='g'||unit==='ml'?500:1);
     const loc=defaultLoc(k.id,f);const lot={id:W.uid(),k:k.id,food:f.id,qty,init:qty,unit,loc,added:Date.now(),pkg:pk?pk[2]:''};st.inv.push(lot);E.tx(lot,'add',E.toBase(qty,unit),'From shopping list');n++;}}
   st.shop=st.shop.filter(s=>!(s.k===k.id&&s.done));W.save();W.render();W.toast(n?n+' item'+(n>1?'s':'')+' added. Check quantities and dates in Stock.':'List cleared. Custom items are not tracked in stock.');}}};
function defaultLoc(k,f){const locs=E.locsFor(k);const t=f&&f.loc;const top=locs.find(l=>l.type===t&&!l.parent);if(top){const kids=locs.filter(l=>l.parent===top.id);return (kids[0]||top).id;}return (locs.find(l=>!l.parent)||{}).id||'';}
W.defaultLoc=defaultLoc;
function lotSheet(id){const l=S().inv.find(x=>x.id===id);if(!l)return;const d=E.daysLeft(l),f=E.food(l.food);
 W.sheet('<div class="row sp"><div><h2>'+e(E.foodName(l))+'</h2><p class="sub">'+e(E.locName(l.loc))+'</p></div><span class="qtybig">'+e(E.fmt(l.qty,l.unit))+'</span></div>'+
 '<div class="card" style="padding:4px 16px">'+[['Freshness',E.daysLabel(d)],['Best-by',l.bestBy||'—'],['Expires',l.exp||'—'],['Opened on',l.opened||'—'],['Brand',l.brand||'—'],['Low-stock alert at',E.fmt(E.lowAt(l),l.unit)],['Contains',f.al.length?f.al.map(a=>R.ALLERGENS[a]||R.INTOL[a]).join(', '):'No listed allergens']].map(x=>'<div class="kv"><span>'+x[0]+'</span><b style="font-weight:500;text-align:right">'+e(x[1])+'</b></div>').join('')+'</div>'+
 '<div class="g2"><button class="btn" data-act="use2">'+W.i('flame')+'Use some</button><button class="btn o" data-act="edit">'+W.i('edit')+'Edit</button><button class="btn o" data-act="shop">'+W.i('cart')+'To list</button><button class="btn o" data-act="waste">Wasted</button></div><button class="btn gh danger" data-act="rm">'+W.i('trash')+'Delete item</button>',
 {label:E.foodName(l),acts:{use2:()=>{W.closeSheet(true);useSheet(id);},edit:()=>{W.closeSheet(true);W.go('addfood',{edit:id});},shop:()=>{const ok=W.addToShop(l.k,l.food,E.foodName(l));W.save();W.closeSheet();W.toast(ok?'Added to shopping list':'Already on your list');},
  waste:()=>{const st=S();st.inv=st.inv.filter(x=>x!==l);E.tx(l,'waste',-E.toBase(l.qty,l.unit));W.save();W.closeSheet();W.render();W.toast('Logged as wasted. Use-soon alerts help cut this down.');},
  rm:()=>{W.closeSheet(true);W.screens.inventory.acts.del({dataset:{id}});}}});}
function useSheet(id){const l=S().inv.find(x=>x.id===id);if(!l)return;const dim=E.unitDim(l.unit);const step=dim==='count'?1:(['kg','l','lb','gallon'].includes(l.unit)?0.25:(l.unit==='g'||l.unit==='ml'?50:1));W.f._use=Math.min(+l.qty,step);
 const draw=()=>'<h2>Use '+e(E.foodName(l))+'</h2><p>You have '+e(E.fmt(l.qty,l.unit))+'.</p><div class="row sp card"><b style="font-size:20px">'+e(E.fmt(W.f._use,l.unit))+'</b>'+W.step('','ud','',-1)+'</div><div class="g2"><button class="btn o" data-act="half">Half</button><button class="btn o" data-act="all">All of it</button></div><button class="btn" data-act="ok">Use '+e(E.fmt(W.f._use,l.unit))+'</button>';
 W.sheet(draw(),{label:'Use item',acts:{ud:el=>{W.f._use=Math.max(0,Math.min(+l.qty,Math.round((W.f._use+step*(+el.dataset.d))*100)/100));W.resheet(draw());},half:()=>{W.f._use=Math.round(l.qty/2*100)/100;W.resheet(draw());},all:()=>{W.f._use=+l.qty;W.resheet(draw());},
  ok:()=>{const u=+W.f._use;if(!(u>0)){W.closeSheet();return;}const st=S();l.qty=Math.round((l.qty-u)*1000)/1000;E.tx(l,'use',-E.toBase(u,l.unit));if(l.qty<=0){st.inv=st.inv.filter(x=>x!==l);W.addToShop(l.k,l.food,E.foodName(l),'Used up');}W.save();W.closeSheet();W.render();W.toast(l.qty<=0?E.foodName(l)+' used up and added to your shopping list':'Updated: '+E.fmt(l.qty,l.unit)+' left');}}});}
W.useSheet=useSheet;W.lotSheet=lotSheet;
/* ---- Add / edit food (Step 7) ---- */
W.screens.addfood={render(p){const st=S(),k=E.kitchen();if(!k)return '';const f=W.f;const edit=p.edit&&st.inv.find(x=>x.id===p.edit);
 if(f._init==null){f._init=1;if(edit){Object.assign(f,{name:E.foodName(edit),food:edit.food,qty:edit.qty,unit:edit.unit,loc:edit.loc,pkg:edit.pkg||'',packs:edit.packs||'',bestBy:edit.bestBy||'',exp:edit.exp||'',brand:edit.brand||'',opened:edit.opened||'',low:edit.low==null?'':edit.low});}else{f.unit='';f.qty='';f.packs='1';}}
 const food=f.food?E.food(f.food):null;const dim=food&&food.dim?food.dim:(food?E.unitDim(food.u[k.units]):(f.unit?E.unitDim(f.unit):null));
 const us=R.UNIT_SETS[k.units];const units=food?us[dim]:us.count.concat(us.mass,us.volume);if(food&&!f.unit)f.unit=food.u?food.u[k.units]:units[0];if(!f.unit)f.unit='each';
 const locs=E.locsFor(k.id);if(!f.loc&&locs.length)f.loc=defaultLoc(k.id,food);
 const pk=food?((R.PKG[k.country]||{})[food.id]||[]):[];const sug=!f.food&&f.name?E.search(f.name):[];const added=st.ui.addedNow||[];
 const custom=!food&&String(f.name||'').trim().length>1;
 return '<div class="scr">'+(p.setup?W.top('Step 7 of 8',{pct:88}):W.top(edit?'Edit food':'Add food'))+'<div class="scroll"><div><h1>'+(edit?'Edit food':'Add food')+'</h1><p class="sub">'+e(k.name)+' kitchen · '+(k.units==='us'?'U.S.':'metric')+' units</p></div>'+
 W.field('What are you adding?','name',{ph:'e.g. eggs, leite, Eier',ac:'off'})+
 (food?'<div class="row" style="gap:10px;flex-wrap:wrap"><span class="badge-m">✓ Matched: '+e(food.name)+'</span><span class="sub">Local names work</span>'+(food.al&&food.al.length?'<span class="pill al">Contains '+e(food.al.filter(a=>R.ALLERGENS[a]).map(a=>R.ALLERGENS[a].toLowerCase()).join(', ')||food.al.map(a=>R.INTOL[a]).join(', ').toLowerCase())+'</span>':'')+'</div>':'')+
 (sug.length?'<div class="sug" role="listbox">'+sug.map(s=>'<button role="option" data-act="pick" data-id="'+s.id+'"><span>'+e(s.name)+'</span><span class="sub">'+e((R.CATS[s.cat]||{}).n||'')+'</span></button>').join('')+'</div>':'')+
 (custom?'<div class="card col"><h3>New item for your household</h3><p class="sub">No match in the food list. Tell us what it is so meal matching and allergy checks work.</p>'+W.field('Category','ccat',{options:R.LEAF_CATS.concat(['pantry']).map(c=>[c,R.CATS[c].n]),ph:'Choose'})+'<div class="sub">Contains (allergens)</div><div class="wr">'+Object.entries(R.ALLERGENS).concat(Object.entries(R.INTOL)).map(([a,n])=>W.chip(n,(f.cal||[]).includes(a),'data-act="cal" data-a="'+a+'"','kc')).join('')+'</div></div>':'')+
 '<div class="row" style="align-items:flex-start">'+W.field('Quantity','qty',{type:'number',mode:'decimal',min:0,step:'any',ph:'0'})+W.field('Unit','unit',{options:units.map(u=>[u,R.UNITS[u][2]])})+'</div>'+
 (locs.length?W.field('Where is it?','loc',{options:locs.map(l=>[l.id,E.locName(l.id)])}):'<div class="alert warn">'+W.i('warn')+'<span>No storage places in this kitchen yet. <button class="lnk" data-act="storage">Add storage</button></span></div>')+
 '<div class="row" style="align-items:flex-start">'+(pk.length?W.field('Package','pkg',{options:pk.map(x=>[x[2],x[2]+' ('+E.fmt(x[0],x[1])+')']),ph:'Custom'}):W.field('Package','pkg',{ph:'e.g. 12 each',opt:1}))+W.field('Packages','packs',{type:'number',mode:'numeric',min:1})+'</div>'+
 '<div class="row" style="align-items:flex-start">'+W.field('Best-by','bestBy',{type:'date',opt:1})+W.field('Expires','exp',{type:'date',opt:1})+'</div>'+
 '<div class="row" style="align-items:flex-start">'+W.field('Brand','brand',{opt:1})+W.field('Opened on','opened',{type:'date',opt:1})+'</div>'+
 W.field('Alert me when below','low',{type:'number',mode:'decimal',min:0,step:'any',opt:1,ph:'Default: a quarter left'})+
 (f._er?'<div class="alert">'+W.i('warn')+'<span>'+e(f._er)+'</span></div>':'')+
 (p.setup&&added.length?'<div class="card"><h3>Added so far</h3><div class="wr mt8">'+added.map(n=>'<span class="pill ok">'+e(n)+'</span>').join('')+'</div></div>':'')+
 '</div><div class="foot"><button class="btn" data-act="save">'+(edit?'Save Changes':'Save Item')+'</button>'+(edit?'':'<button class="btn o" data-act="another">Add Another</button>')+(p.setup?'<button class="btn gh" data-act="skipinv">'+(st.inv.length?'Done adding food':'Skip for now')+'</button>':'')+'</div></div>';},
 onInput(k){const f=W.f;if(k==='name'){const m=E.exact(f.name);const before=f.food;f.food=m?m.id:'';if(m&&m.id!==before){f.unit='';f.loc='';f.pkg='';}if(f.food!==before||!f.food)W.render();}
  if(k==='packs'||k==='pkg')applyPkg();},
 onChange(k){if(k==='pkg'){applyPkg();W.render();}if(k==='unit'&&!W.f.food)W.render();},
 acts:{pick:el=>{const fd=E.food(el.dataset.id);Object.assign(W.f,{food:fd.id,name:fd.name,unit:'',loc:'',pkg:''});W.render();},
  cal:el=>{const a=el.dataset.a,c=W.f.cal=W.f.cal||[];c.includes(a)?c.splice(c.indexOf(a),1):c.push(a);W.render();},
  storage:()=>W.go('storage',{}),save:()=>saveFood(false),another:()=>saveFood(true),
  skipinv:()=>{const p=W.stack[W.stack.length-1].p;S().setup.inventory=S().inv.length?'done':'skipped';S().ui.addedNow=[];W.save();W.setupNext('inventory');}}};
function applyPkg(){const f=W.f,k=E.kitchen();const pk=f.food?((R.PKG[k.country]||{})[f.food]||[]).find(x=>x[2]===f.pkg):null;const n=Math.max(1,+f.packs||1);
 if(pk){f.unit=pk[1];f.qty=String(Math.round(pk[0]*n*1000)/1000);W.render();}else{const m=String(f.pkg||'').match(/^\s*([\d.]+)\s*([a-z ]+)?/i);if(m&&m[1]){const u=(m[2]||'').trim().toLowerCase().replace('ea','each').replace('eachch','each');if(R.UNITS[u])f.unit=u;f.qty=String(+m[1]*n);W.render();}}}
function saveFood(again){const t=W.stack[W.stack.length-1],p=t.p,f=W.f,st=S(),k=E.kitchen();const name=String(f.name||'').trim();
 if(!name){f._er='Tell us what you’re adding.';W.render();return;}if(!(+f.qty>0)){f._er='Enter a quantity above 0.';W.render();return;}
 let foodId=f.food;if(!foodId){if(!f.ccat){f._er='Choose a category for this new item.';W.render();return;}const cf={id:'c_'+W.uid().slice(0,8),name,cat:f.ccat,al:(f.cal||[]).slice(),alias:'',u:{us:f.unit,metric:f.unit},life:14,loc:'pantry',custom:true};st.foods.push(cf);foodId=cf.id;}
 const fd=E.food(foodId);if(E.unitDim(f.unit)!==E.unitDim(fd.u?fd.u[k.units]:f.unit)&&!fd.custom){f._er=fd.name+' is measured by '+E.unitDim(fd.u[k.units])+'. Pick a matching unit.';W.render();return;}
 const data={food:foodId,name:fd.custom?'':(E.norm(name)===E.norm(fd.name)?'':''),qty:+f.qty,unit:f.unit,loc:f.loc||'',pkg:f.pkg||'',packs:f.packs||'',bestBy:f.bestBy||'',exp:f.exp||'',brand:String(f.brand||'').trim(),opened:f.opened||'',low:f.low===''||f.low==null?null:+f.low};
 const edit=p.edit&&st.inv.find(x=>x.id===p.edit);
 if(edit){const delta=E.toBase(data.qty,data.unit)-E.toBase(edit.qty,edit.unit);Object.assign(edit,data);if(Math.abs(delta)>1e-9)E.tx(edit,'adjust',delta);W.save();W.back();W.toast('Saved');return;}
 const lot=Object.assign({id:W.uid(),k:k.id,init:data.qty,added:Date.now()},data);st.inv.push(lot);E.tx(lot,'add',E.toBase(lot.qty,lot.unit));
 if(p.setup){st.ui.addedNow=(st.ui.addedNow||[]).concat(fd.name);}
 W.save();W.toast(fd.name+' saved');
 if(again){W.f={_init:1,unit:'',qty:'',packs:'1',loc:''};W.render(true);const i=document.querySelector('[data-f="name"]');i&&i.focus();}
 else if(p.setup){st.setup.inventory='done';st.ui.addedNow=[];W.save();W.setupNext('inventory');}else W.back();}
return true;});
