/* Meals: matching results, recipe detail with explainable reasons, cook (deducts stock), history */
W.def('meals', function(W){
const R=W.use('ref'),E=W.use('engine'),e=W.e,S=()=>W.S;
W.eaters=k=>{const st=S();st.ui.eaters=st.ui.eaters||{};if(!st.ui.eaters[k])st.ui.eaters[k]=E.membersIn(k).map(m=>m.id);if(!st.ui.eaters[k].length)st.ui.eaters[k]=st.members.map(m=>m.id);return st.ui.eaters[k].filter(id=>st.members.some(m=>m.id===id));};
const sevIc={block:'x',warn:'warn',good:'check',info:'cart'};
const line=x=>{if(x.type==='allergy')return '<b>Allergy · '+e(x.member)+':</b> '+e(x.detail);if(x.type==='appliance')return '<b>'+e(x.detail.replace(/^needs /,'Needs '))+'</b> in this kitchen.';return (x.sev==='good'?'✓ ':x.sev==='warn'?'⚠ ':'')+(x.member?e(x.member)+' · ':'')+e(x.detail);};
W.screens.meals={tab:'meals',render(){const st=S(),k=E.kitchen();if(!k)return '';const mode=st.ui.mealMode||'sug';const eat=W.eaters(k.id);
 let h='<div class="scr"><div class="scroll"><div class="row sp" style="margin-top:8px"><div><h1>What can we cook?</h1><p class="sub">'+e(k.name)+' kitchen</p></div>'+W.logo(44)+'</div>'+W.kSwitch()+
  '<div class="seg" role="tablist"><button role="tab" class="'+(mode==='sug'?'on':'')+'" data-act="mm" data-m="sug">Suggestions</button><button role="tab" class="'+(mode==='hist'?'on':'')+'" data-act="mm" data-m="hist">History</button></div>';
 if(mode==='sug'){h+='<div><div class="sub" style="margin-bottom:6px">Who’s eating?</div><div class="ksw">'+st.members.map(m=>W.chip(m.name,eat.includes(m.id),'data-act="eat" data-id="'+m.id+'"','kc')).join('')+'</div></div>';
  if(!eat.length)h+=W.empty('Pick who’s eating','Suggestions check everyone’s allergies, diets and tastes.','');
  else{const res=E.match(k.id,eat);const ok=res.filter(x=>!x.blocked),bad=res.filter(x=>x.blocked);const showAll=W.f.all;
   if(!E.lots(k.id).length)h+='<div class="alert warn">'+W.i('warn')+'<span>No food in this kitchen yet, so availability is 0%. <button class="lnk" data-act="addf">Add food</button></span></div>';
   h+='<div class="list">'+ok.map(card).join('')+'</div>';
   if(bad.length){h+='<button class="btn gh" data-act="all">'+(showAll?'Hide':'Show')+' '+bad.length+' not suitable</button>';if(showAll)h+='<div class="list">'+bad.map(card).join('')+'</div>';}}}
 else{const ms=st.meals.filter(m=>m.k===k.id);if(!ms.length)h+=W.empty('No meals logged yet','When you cook a suggestion, it is saved here with who ate and what was used.','');
  else h+='<div class="list">'+ms.map(m=>{const r=R.RECIPES.find(x=>x.id===m.r)||{title:m.title||'Meal'};const who=m.who.map(id=>(st.members.find(x=>x.id===id)||{}).name).filter(Boolean);return '<button class="item" data-act="hm" data-id="'+m.id+'"><span class="num done">'+W.i('check')+'</span><span class="grow"><b>'+e(r.title)+'</b><span>'+e(new Date(m.at).toLocaleDateString(undefined,{weekday:'short',month:'short',day:'numeric'}))+' · '+m.serv+' servings'+(who.length?' · '+e(who.join(', ')):'')+'</span></span></button>';}).join('')+'</div>';}
 return h+'</div></div>';},
 acts:{mm:el=>{S().ui.mealMode=el.dataset.m;W.save();W.render(true);},eat:el=>{const k=E.kitchen().id,a=W.eaters(k),id=el.dataset.id;const n=a.includes(id)?a.filter(x=>x!==id):a.concat(id);S().ui.eaters[k]=n;W.save();W.render();},
  all:()=>{W.f.all=!W.f.all;W.render();},open:el=>W.go('recipe',{id:el.dataset.id}),addf:()=>W.go('addfood',{}),
  hm:el=>{const st=S(),m=st.meals.find(x=>x.id===el.dataset.id);const r=R.RECIPES.find(x=>x.id===m.r)||{title:'Meal'};W.sheet('<h2>'+e(r.title)+'</h2><p>'+e(new Date(m.at).toLocaleString())+'</p><div class="card" style="padding:4px 16px">'+(m.used||[]).map(u=>'<div class="kv"><span>'+e(u.n)+'</span><b style="font-weight:500">'+e(u.q)+'</b></div>').join('')+'</div><button class="btn o" data-act="again">Cook again</button><button class="btn gh danger" data-act="rmh">Remove from history</button>',{label:r.title,acts:{again:()=>{W.closeSheet(true);W.go('recipe',{id:m.r});},rmh:()=>{W.commit(s=>{s.meals=s.meals.filter(x=>x.id!==m.id);});W.closeSheet();}}});}}};
function card(x){const r=x.r;const shown=x.reasons.filter(z=>z.sev!=='info').sort((a,b)=>({block:0,warn:1,good:2}[a.sev]-{block:0,warn:1,good:2}[b.sev])).slice(0,3);
 return '<button class="rc'+(x.blocked?' bad':'')+'" data-act="open" data-id="'+r.id+'"><div class="row sp"><h3>'+e(r.title)+'</h3>'+(x.blocked?'<span class="pill al">Not suitable</span>':'<span class="pill ok">'+x.fit+'% fit</span>')+'</div>'+
 (x.blocked?'':'<div class="ln">Ingredients available: '+x.avail+'% · '+r.mins+' min</div>')+shown.map(z=>'<div class="ln">'+line(z)+'</div>').join('')+'</button>';}
W.screens.recipe={render(p){const st=S(),k=E.kitchen(),r=R.RECIPES.find(x=>x.id===p.id);if(!r)return '';const x=E.match(k.id,W.eaters(k.id)).find(z=>z.r.id===r.id);const stock=E.stock(k.id);
 const groups={block:'Not suitable because',warn:'Heads up',good:'Good fit'};
 let h='<div class="scr">'+W.top('Meal')+'<div class="scroll"><div class="row sp" style="align-items:flex-start"><h1>'+e(r.title)+'</h1>'+(x.blocked?'<span class="pill al">Not suitable</span>':'<span class="pill ok">'+x.fit+'% fit</span>')+'</div>'+
  '<div class="g4" style="grid-template-columns:repeat(3,1fr)"><div class="stat"><b>'+x.avail+'%</b><span>In stock</span></div><div class="stat"><b>'+r.mins+'</b><span>Minutes</span></div><div class="stat"><b>'+r.serv+'</b><span>Servings</span></div></div>';
 for(const sev of ['block','warn','good']){const rs=x.reasons.filter(z=>z.sev===sev);if(!rs.length)continue;h+='<div class="alert '+(sev==='block'?'':sev==='warn'?'warn':'ok')+'">'+W.i(sevIc[sev])+'<div><b>'+groups[sev]+'</b>'+rs.map(z=>'<div>'+line(z)+'</div>').join('')+(sev==='block'&&rs.some(z=>z.type==='appliance')?'<button class="lnk" data-act="appl" style="padding:0">Add appliance</button>':'')+'</div></div>';}
 h+='<div class="gl">Ingredients</div><div class="card" style="padding:2px 16px">'+r.ing.map(i=>{const f=E.food(i.f),dim=E.unitDim(i.u),need=E.toBase(i.q,i.u),have=((stock[i.f]||{})[dim])||0;const ok=have>=need;
  return '<div class="ing"><span class="'+(ok?'ok-ic':'no-ic')+'">'+W.i(ok?'check':'x')+'</span><span class="grow">'+e(f.name)+(i.opt?' <span class="sub">(optional)</span>':'')+'</span><span class="sub">'+e(E.pretty(need,dim,k.units))+(ok||!have?'':' · have '+e(E.pretty(have,dim,k.units)))+'</span></div>';}).join('')+'</div>';
 if(x.missing.length)h+='<button class="btn o" data-act="miss">'+W.i('cart')+'Add '+x.missing.length+' missing to shopping list</button>';
 h+='<div class="gl">Needs</div><p>'+(r.app.length?r.app.map(a=>'<span class="pill '+(E.hasItem(k.id,a)?'ok':'al')+'" style="margin-right:6px">'+e(a.replace(/_/g,' '))+'</span>').join(''):'No appliances needed')+'</p>';
 h+='<div class="gl">Steps</div><ol style="margin:0;padding-left:22px;display:flex;flex-direction:column;gap:8px">'+r.steps.map(s=>'<li>'+e(s)+'</li>').join('')+'</ol>';
 h+='<div class="gl">Per serving</div><div class="card" style="padding:4px 16px">'+Object.entries(R.NUTR).map(([kk,n])=>'<div class="kv"><span>'+n+'</span><b style="font-weight:500">'+r.n[kk]+(kk==='cal'?' kcal':kk==='sodium'?' mg':' g')+'</b></div>').join('')+'</div><p class="sub">Nutrition values are estimates for matching, not medical advice.</p>';
 h+='</div><div class="foot">'+(x.blocked?'<button class="btn" disabled>Not suitable for who’s eating</button>':'<button class="btn y" data-act="cook">Cook this</button>')+'</div></div>';return h;},
 acts:{appl:()=>W.go('items',{tab:'appliances'}),
  miss:()=>{const t=W.stack[W.stack.length-1],k=E.kitchen(),x=E.match(k.id,W.eaters(k.id)).find(z=>z.r.id===t.p.id);let n=0;for(const m of x.missing){if(W.addToShop(k.id,m.f,E.food(m.f).name,'For '+x.r.title))n++;}W.save();W.toast(n?n+' added to your shopping list':'Already on your list');},
  cook:()=>cookSheet(W.stack[W.stack.length-1].p.id)}};
function cookSheet(id){const k=E.kitchen(),r=R.RECIPES.find(x=>x.id===id);W.f._serv=r.serv;W.f._who=W.eaters(k.id).slice();
 const draw=()=>'<h2>Cook '+e(r.title)+'</h2><p>We’ll take the ingredients out of your '+e(k.name)+' stock, oldest first, and save the meal to history.</p><div class="card row sp"><b>Servings</b>'+W.step(W.f._serv,'sv','',1)+'</div><div class="sub">Who ate?</div><div class="wr">'+S().members.map(m=>W.chip(m.name,W.f._who.includes(m.id),'data-act="who" data-id="'+m.id+'"','kc')).join('')+'</div><button class="btn y" data-act="go">Cooked it</button>';
 W.sheet(draw(),{label:'Cook',acts:{sv:el=>{W.f._serv=Math.max(1,W.f._serv+(+el.dataset.d));W.resheet(draw());},who:el=>{const a=W.f._who,i=el.dataset.id;W.f._who=a.includes(i)?a.filter(x=>x!==i):a.concat(i);W.resheet(draw());},
  go:()=>{const st=S(),f=W.f._serv/r.serv,used=[];let short=0;
   for(const i of r.ing){const dim=E.unitDim(i.u);const need=E.toBase(i.q,i.u)*f;const got=E.consume(k.id,i.f,need,dim,'cook');if(got>0)used.push({n:E.food(i.f).name,q:E.pretty(got,dim,k.units)});if(got+1e-6<need&&!i.opt)short++;}
   st.meals.unshift({id:W.uid(),r:r.id,k:k.id,at:Date.now(),serv:W.f._serv,who:W.f._who.slice(),used});
   for(const l of E.lots(k.id))if(E.isLow(l))W.addToShop(k.id,l.food,E.foodName(l),'Running low');
   W.save();W.closeSheet();W.go('meals',{},{root:true});S().ui.mealMode='hist';W.render();W.toast('Enjoy! Stock updated'+(short?' ('+short+' item'+(short>1?'s were':' was')+' short)':'')+'.');}}});}
return true;});
