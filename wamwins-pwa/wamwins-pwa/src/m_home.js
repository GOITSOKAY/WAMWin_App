/* Home dashboard */
W.def('home', function(W){
const R=W.use('ref'),E=W.use('engine'),e=W.e,S=()=>W.S;
const greet=()=>{const h=new Date().getHours();return h<5?'Good evening':h<12?'Good morning':h<18?'Good afternoon':'Good evening';};
W.screens.home={tab:'home',render(){const st=S(),k=E.kitchen();if(!k)return '';const lots=E.lots(k.id);const soon=lots.filter(E.isUseSoon).sort((a,b)=>E.expiry(a)-E.expiry(b));const low=lots.filter(E.isLow);
 const eat=(st.ui.eaters&&st.ui.eaters[k.id])||E.membersIn(k.id).map(m=>m.id);const fit=E.match(k.id,eat.length?eat:st.members.map(m=>m.id)).filter(x=>!x.blocked);const ready=fit.filter(x=>x.avail>=80).length;
 const done=R.STEPS.filter(s=>['done','skipped'].includes(st.setup[s[0]])).length;const al=E.alerts(k.id);
 let h='<div class="scr"><div class="scroll"><div class="row sp" style="margin-top:8px"><div class="grow"><p>'+greet()+', '+e(st.about.name||(st.account||{}).first||'')+'</p><h1>'+e((st.household||{}).name||'Your household')+'</h1></div>'+W.logo(52)+'</div>'+W.kSwitch()+
 (done<8?'<button class="card w row" data-act="setup" style="text-align:left;cursor:pointer;color:var(--t1)"><span class="grow"><b>Finish setting up</b><span class="sub" style="display:block">'+done+' of 8 steps complete</span><span class="bar" style="display:block;margin:8px 0 0"><i style="width:'+(done/8*100)+'%"></i></span></span>'+W.i('chev')+'</button>':'')+
 '<div class="hero"><h2>What should we cook?</h2><p>'+(fit.length?fit.length+' meal'+(fit.length>1?'s':'')+' fit this kitchen and your family'+(ready?', '+ready+' ready with what you have.':'.'):'Add food and appliances to get suggestions.')+'</p><button class="btn y" data-act="meals">See meals</button></div>'+
 '<div class="g4"><button class="stat" data-act="inv" data-f="all"><b>'+lots.length+'</b><span>Items</span></button><button class="stat" data-act="inv" data-f="soon"><b>'+soon.filter(l=>!E.isExpired(l)).length+'</b><span>Use soon</span></button><button class="stat" data-act="inv" data-f="low"><b>'+low.length+'</b><span>Low</span></button><button class="stat" data-act="meals"><b>'+fit.length+'</b><span>Meals</span></button></div>';
 if(soon.length)h+='<div class="lb">Use soon</div><div class="list">'+soon.slice(0,4).map(l=>{const d=E.daysLeft(l);return '<button class="item" data-act="lot" data-id="'+l.id+'"><span class="grow"><b>'+e(E.foodName(l))+'</b><span>'+e(E.locName(l.loc))+'</span></span><span class="pill'+(d<0?' al':'')+'">'+E.daysLabel(d)+'</span></button>';}).join('')+'</div>';
 for(const a of al.slice(0,2))h+='<div class="alert">'+W.i('warn')+'<span><b>Heads up:</b> '+e(a.text)+'</span></div>';
 if(low.length)h+='<div class="lb">Running low</div><div class="list">'+low.slice(0,3).map(l=>'<div class="item" style="cursor:default"><span class="grow"><b>'+e(E.foodName(l))+'</b><span>'+e(E.fmt(l.qty,l.unit))+' left</span></span><button class="btn sm o" data-act="tolist" data-id="'+l.id+'">'+W.i('cart')+'Add</button></div>').join('')+'</div>';
 if(!lots.length)h+=W.empty('Your kitchen is empty','Add the food you have. Suggestions get better with every item.','<button class="btn sm" data-act="add">'+W.i('plus')+'Add Food</button>');
 const last=st.meals.find(m=>m.k===k.id);if(last){const r=R.RECIPES.find(x=>x.id===last.r);if(r)h+='<div class="lb">Last cooked</div><button class="item" data-act="recipe" data-id="'+r.id+'"><span class="num done">'+W.i('check')+'</span><span class="grow"><b>'+e(r.title)+'</b><span>'+e(new Date(last.at).toLocaleDateString(undefined,{weekday:'long'}))+'</span></span>'+W.i('chev')+'</button>';}
 return h+'</div></div>';},
 acts:{setup:()=>W.go('setup',{}),meals:()=>W.go('meals',{},{root:true}),inv:el=>{S().ui.invMode='stock';W.go('inventory',{flt:el.dataset.f},{root:true});},
  lot:async el=>{await W.load('inventory');W.lotSheet(el.dataset.id);},add:()=>W.go('addfood',{}),recipe:el=>W.go('recipe',{id:el.dataset.id}),
  tolist:async el=>{await W.load('inventory');const l=S().inv.find(x=>x.id===el.dataset.id);const ok=W.addToShop(l.k,l.food,E.foodName(l),'Running low');W.save();W.toast(ok?E.foodName(l)+' added to your shopping list':'Already on your list');}}};
return true;});
