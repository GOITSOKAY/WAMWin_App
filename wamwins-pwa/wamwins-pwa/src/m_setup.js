/* Onboarding: setup hub + 8 steps (About You, Household, Family, Food Needs, Storage, Appliances & Tools, Inventory, Matching) */
W.def('setup', function(W){
const R=W.use('ref'),E=W.use('engine'),e=W.e,S=()=>W.S;
const SCREEN={about_you:'about',household:'hh',family_members:'family',food_needs:'needs',kitchen:'storage',appliances_tools:'items',inventory:'addfood',meal_matching:'finish'};
const idx=c=>R.STEPS.findIndex(s=>s[0]===c);
const isDone=c=>['done','skipped'].includes(S().setup[c]);
const doneCount=()=>R.STEPS.filter(s=>isDone(s[0])).length;
W.setupNext=function(after){const st=S();const order=R.STEPS.map(s=>s[0]);let i=after?order.indexOf(after)+1:0;
 for(;i<order.length;i++){if(!isDone(order[i]))break;}if(i>=order.length){for(i=0;i<order.length&&isDone(order[i]);i++);}
 if(i>=order.length){W.go('home',{},{root:true});return;}W.openStep(order[i]);};
W.openStep=function(c){const st=S();if(!st.household&&idx(c)>1){W.toast('Create your household first.');c='household';}
 if(c==='food_needs'){const m=st.members.find(m=>!E.progress(m).done)||st.members[0];if(!m){W.openStep('family_members');return;}W.go('needs',{id:m.id,setup:1});return;}
 W.go(SCREEN[c],{setup:1});};
W.markStep=(c,v)=>{S().setup[c]=v||'done';W.save();};
const stepTop=(c,p,title)=>p.setup?W.top('Step '+(idx(c)+1)+' of 8',{pct:Math.round((idx(c)+1)/8*100)}):W.top(title);
const finishStep=(c,p)=>{W.markStep(c);if(p.setup)W.setupNext(c);else W.back();};
/* ---- hub ---- */
W.screens.setup={render(){const st=S(),n=doneCount();return '<div class="scr"><div class="scroll"><div class="row sp" style="align-items:flex-start;margin-top:8px"><div><p>Welcome to WAMWins Basic, '+e(st.about.name||(st.account||{}).first||'')+'.</p><h1 class="mt8">Let’s set up your household</h1></div>'+W.logo(52)+'</div>'+
 '<div><div class="row sp"><h3>Setup progress</h3><b style="font-size:14px">'+n+' of 8 complete</b></div><div class="bar mt8" style="margin:8px 0 0"><i style="width:'+(n/8*100)+'%"></i></div></div>'+
 '<div class="card steps" style="padding:8px 12px">'+R.STEPS.map((s,i)=>{const v=st.setup[s[0]];return '<button data-act="step" data-c="'+s[0]+'"><span class="num'+(v==='done'?' done':v==='skipped'?' skip':'')+'">'+(v==='done'?W.i('check'):v==='skipped'?'–':i+1)+'</span><span class="grow">'+s[1]+'</span>'+(v==='skipped'?'<span class="pill mu">Skipped</span>':'')+'</button>';}).join('')+'</div>'+
 '<p class="sub">Your progress is saved. Pick up where you left off any time.</p></div><div class="foot"><button class="btn y" data-act="cont">'+(n===8?'Go to Home':'Continue Setup')+'</button>'+(n<8?'<button class="btn o" data-act="later">I’ll Do This Later</button>':'')+'</div></div>';},
 acts:{step:el=>W.openStep(el.dataset.c),cont:()=>W.setupNext(),later:()=>{if(!S().household){W.toast('Create your household first. It takes 20 seconds.');W.openStep('household');return;}W.go('home',{},{root:true});}}};
/* ---- 1 About you ---- */
W.screens.about={render(p){const a=S().about,f=W.f;if(f.role==null){f.role=a.role||'';f.goals=(a.goals||[]).slice();}
 return '<div class="scr">'+stepTop('about_you',p,'About you')+'<div class="scroll"><div><h1>About you</h1><p class="mt8">This personalizes your home screen.</p></div>'+W.field('What should we call you?','name',{value:a.name||(S().account||{}).first||'',ac:'nickname',err:f._er})+
 '<div class="lb">Your role in this household</div><div class="wr">'+Object.entries(R.ROLES).map(([k,v])=>W.chip(v,f.role===k,'data-act="role" data-k="'+k+'"')).join('')+'</div>'+
 '<div class="lb">What would you like help with?</div><div class="wr">'+Object.entries(R.GOALS).map(([k,v])=>W.chip(v,f.goals.includes(k),'data-act="goal" data-k="'+k+'"')).join('')+'</div></div><div class="foot"><button class="btn" data-act="save">Continue</button></div></div>';},
 acts:{role:el=>{W.f.role=el.dataset.k;W.render();},goal:el=>{const g=W.f.goals,k=el.dataset.k;g.includes(k)?g.splice(g.indexOf(k),1):g.push(k);W.render();},
  save:(el)=>{const p=W.stack[W.stack.length-1].p;const name=String(W.f.name!=null?W.f.name:(S().about.name||(S().account||{}).first||'')).trim();if(!name){W.f._er='Tell us what to call you.';W.render();return;}
   const st=S();st.about={name,role:W.f.role,goals:W.f.goals};const me=st.members.find(m=>m.self);if(me)me.name=name;finishStep('about_you',p);}}};
/* ---- 2 Household ---- */
W.kitchenFrom=(country,region)=>{const c=R.COUNTRIES[country]||['','metric','en',''];let tz='';try{tz=Intl.DateTimeFormat().resolvedOptions().timeZone;}catch(_){}
 return {id:W.uid(),name:(region||c[0]||'Main').trim(),country,region:region||'',units:c[1],locale:c[2],tz:country===((S().household||{}).country)||!S().household?(tz||c[3]):c[3]};};
const tzLabel=tz=>{if(!tz)return '';try{const n=new Intl.DateTimeFormat('en-US',{timeZone:tz,timeZoneName:'long'}).formatToParts(new Date()).find(x=>x.type==='timeZoneName');return n?n.value.replace(/ (Standard|Daylight)/,''):tz;}catch(_){return tz;}};
W.tzLabel=tzLabel;
W.screens.hh={render(p){const st=S(),h=st.household||{},f=W.f,main=st.kitchens[0];
 if(f.country==null){f.country=h.country||guessCountry();f.region=h.region||'';f.people=h.people||Math.max(1,st.members.length||1);f.hname=h.name||((st.account&&st.account.last)?'The '+st.account.last+' Family':'');}
 const c=R.COUNTRIES[f.country]||['','metric','en',''];let tz='';try{tz=Intl.DateTimeFormat().resolvedOptions().timeZone;}catch(_){}
 return '<div class="scr">'+stepTop('household',p,'Household')+'<div class="scroll"><div><h1>Tell us about your household</h1><p class="mt8">'+(st.household?'Update your household details.':'This creates your household and your first kitchen.')+'</p></div>'+
 W.field('Household name','hname',{ph:'The Silva Family',err:f._er})+
 '<div class="fld"><span>People who regularly eat from your kitchens</span>'+W.step(f.people,'ppl','',1)+'</div>'+
 '<div class="row" style="align-items:flex-start">'+W.field('Country','country',{options:Object.entries(R.COUNTRIES).map(([k,v])=>[k,v[0]]).sort((a,b)=>a[1].localeCompare(b[1]))})+
 (f.country==='US'?W.field('State','region',{options:R.US_STATES.map(s=>[s,s]),ph:'Choose'}):W.field('City or region','region',{ph:'e.g. São Paulo'}))+'</div>'+
 '<div class="card"><h3>'+e(main?main.name+' kitchen':'Main Kitchen')+'</h3><p class="sub mt8">'+(c[1]==='us'?'U.S. units':'Metric units')+' · '+({en:'English',pt:'Portuguese',de:'German',es:'Spanish',fr:'French',it:'Italian'}[c[2]]||'English')+' · '+e(tzLabel(main?main.tz:tz)||'Local time')+' (detected). You can add kitchens in other countries later.</p></div>'+
 '</div><div class="foot"><button class="btn" data-act="save">'+(st.household?'Save Household':'Create Household')+'</button></div></div>';},
 onChange(k){if(k==='country'){W.f.region='';W.render();}},
 acts:{ppl:el=>{W.f.people=Math.max(1,(+W.f.people||1)+(+el.dataset.d));W.render();},
  save:()=>{const p=W.stack[W.stack.length-1].p,f=W.f,st=S();const name=String(f.hname||'').trim();if(!name){f._er='Give your household a name.';W.render();return;}
   if(!st.household){const k=W.kitchenFrom(f.country,f.region);st.household={id:W.uid(),name,people:f.people,country:f.country,region:f.region,created:Date.now()};st.kitchens=[k];st.active=k.id;
    st.members.push({id:W.uid(),self:true,name:st.about.name||(st.account||{}).first||'Me',rel:'self',role:st.about.role,band:'age_18_64',age:'',k:k.id,answers:{}});
    st.setup.household='done';W.save();W.toast('Household created');finishStep('household',p);}
   else{Object.assign(st.household,{name,people:f.people,country:f.country,region:f.region});const k=st.kitchens[0];if(k&&(k.country!==f.country||k.region!==f.region)){const nk=W.kitchenFrom(f.country,f.region);Object.assign(k,{name:nk.name,country:nk.country,region:nk.region,units:nk.units,locale:nk.locale});}finishStep('household',p);}}}};
function guessCountry(){try{const l=(navigator.language||'en-US').split('-')[1];if(l&&R.COUNTRIES[l.toUpperCase()])return l.toUpperCase();}catch(_){}return 'US';}
/* ---- 3 Family members ---- */
W.memberLine=m=>{const k=S().kitchens.find(x=>x.id===m.k);return [m.self?(R.ROLES[S().about.role]||'Me'):R.RELS[m.rel]||'',m.rel==='child'||!m.self&&m.age?E.ageLabel(m):'',k?k.name:''].filter(Boolean).join(' · ');};
W.memberPill=m=>{const pr=E.progress(m);return pr.done?'<span class="pill ok">Complete</span>':pr.n?'<span class="pill">'+pr.n+' of '+pr.total+' answered</span>':'<span class="pill">Needs food needs</span>';};
W.screens.family={render(p){const st=S();const ppl=(st.household||{}).people||0;
 return '<div class="scr">'+stepTop('family_members',p,'Family members')+'<div class="scroll"><div><h1>Who is part of your household?</h1><p class="mt8">Everyone you cook for. Add their home kitchen.</p></div>'+
 '<div class="list">'+st.members.map(m=>'<button class="item" data-act="edit" data-id="'+m.id+'">'+W.av(m.name)+'<span class="grow"><b>'+e(m.name)+'</b><span>'+e(W.memberLine(m))+'</span></span>'+W.memberPill(m)+'</button>').join('')+'</div>'+
 '<button class="btn o" data-act="add">'+W.i('plus')+' Add Family Member</button>'+(ppl>st.members.length?'<p class="sub">You said '+ppl+' people eat from your kitchens. '+st.members.length+' profile'+(st.members.length===1?'':'s')+' so far.</p>':'')+
 '<div class="alert warn">'+W.i('shield')+'<span>Members are profiles, not logins. Your Free plan includes 1 account.</span></div></div>'+
 '<div class="foot"><button class="btn" data-act="cont">Continue</button></div></div>';},
 acts:{edit:el=>W.go('member',{id:el.dataset.id}),add:()=>W.go('member',{}),cont:()=>{const p=W.stack[W.stack.length-1].p;finishStep('family_members',p);}}};
W.screens.member={render(p){const st=S(),m=st.members.find(x=>x.id===p.id),f=W.f;
 if(f.rel==null){f.rel=m?m.rel:'child';f.band=m?m.band:'';f.k=m?m.k:st.active||(st.kitchens[0]||{}).id;f.name=m?m.name:'';f.age=m?m.age:'';}
 return '<div class="scr">'+W.top(m?'Edit profile':'New profile')+'<div class="scroll"><h1>'+(m?e(m.name):'Add a family member')+'</h1>'+
 W.field('Name','name',{ph:'e.g. Sofia',err:f._er,ac:'off'})+
 (m&&m.self?'':'<div class="lb">Relationship</div><div class="wr">'+Object.entries(R.RELS).filter(x=>x[0]!=='self').map(([k,v])=>W.chip(v,f.rel===k,'data-act="rel" data-k="'+k+'"')).join('')+'</div>')+
 '<div class="lb">Age range</div><p class="sub">Questions are matched to age, for example foods not given to toddlers yet.</p><div class="wr">'+R.AGE_BANDS.map(b=>W.chip(b[1],f.band===b[0],'data-act="band" data-k="'+b[0]+'"')).join('')+'</div>'+
 W.field('Exact age','age',{type:'number',mode:'numeric',min:0,opt:1,ph:'e.g. 8'})+
 '<div class="lb">Home kitchen</div><div class="wr">'+st.kitchens.map(k=>W.chip(k.name+' · '+k.country,f.k===k.id,'data-act="kit" data-k="'+k.id+'"')).join('')+'<button class="chip" data-act="newk">'+W.i('plus')+'Other place</button></div>'+
 (m?'<button class="btn o" data-act="needs">Food needs '+W.memberPill(m)+'</button>':'')+(m&&!m.self?'<button class="btn gh danger" data-act="del">Remove profile</button>':'')+
 '</div><div class="foot"><button class="btn" data-act="save">'+(m?'Save Profile':'Add Profile')+'</button></div></div>';},
 onInput(k){if(k==='age'){const a=+W.f.age;if(W.f.age!==''&&a>=0){const b=R.AGE_BANDS.find(x=>a>=x[2]&&a<x[3]);if(b&&b[0]!==W.f.band){W.f.band=b[0];W.render();}}}},
 acts:{rel:el=>{W.f.rel=el.dataset.k;W.render();},band:el=>{W.f.band=el.dataset.k;W.f.age='';W.render();},kit:el=>{W.f.k=el.dataset.k;W.render();},
  newk:()=>W.newKitchenSheet(k=>{W.f.k=k.id;W.render();}),
  needs:()=>{const p=W.stack[W.stack.length-1].p;saveMember(p,true);},
  del:async()=>{const p=W.stack[W.stack.length-1].p;const m=S().members.find(x=>x.id===p.id);if(await W.confirm({title:'Remove '+m.name+'?',body:'Their food needs are deleted too. Meal history stays.',ok:'Remove',danger:1})){W.commit(s=>{s.members=s.members.filter(x=>x.id!==p.id);});W.back();W.toast('Profile removed');}},
  save:()=>saveMember(W.stack[W.stack.length-1].p)}};
function saveMember(p,toNeeds){const f=W.f,st=S();const name=String(f.name||'').trim();if(!name){f._er='Enter a name.';W.render();return;}if(!f.band){W.toast('Choose an age range.');return;}
 let m=st.members.find(x=>x.id===p.id);if(!m){m={id:W.uid(),answers:{}};st.members.push(m);}Object.assign(m,{name,rel:m.self?'self':f.rel,band:f.band,age:f.age===''||f.age==null?'':Math.max(0,Math.round(+f.age)),k:f.k});
 if(m.self)st.about.name=name;W.save();if(toNeeds||!p.id){if(!p.id)W.stack.pop();W.go('needs',{id:m.id,fromMember:1});}else{W.back();W.toast('Profile saved');}}
W.newKitchenSheet=function(done){W.f._nkc=W.f._nkc||'US';const draw=()=>'<h2>Add a kitchen</h2><p>For family who live and cook somewhere else. Each kitchen keeps its own units, storage and food.</p>'+W.field('Country','_nkc',{options:Object.entries(R.COUNTRIES).map(([k,v])=>[k,v[0]]).sort((a,b)=>a[1].localeCompare(b[1]))})+(W.f._nkc==='US'?W.field('State','_nkr',{options:R.US_STATES.map(s=>[s,s]),ph:'Choose'}):W.field('City','_nkr',{ph:'e.g. München'}))+'<p class="sub">'+((R.COUNTRIES[W.f._nkc]||[])[1]==='us'?'U.S. units':'Metric units')+' will be used here.</p><button class="btn" data-act="mk">Add Kitchen</button>';
 W.sheet(draw(),{label:'Add a kitchen',onChange:k=>{if(k==='_nkc'){W.f._nkr='';W.resheet(draw());}},acts:{mk:()=>{const r=String(W.f._nkr||'').trim();if(!r){W.toast('Add a city or state.');return;}const k=W.kitchenFrom(W.f._nkc,r);S().kitchens.push(k);W.save();W.closeSheet();W.toast(k.name+' kitchen added');done&&done(k);}}});};
/* ---- 4 Food needs questionnaire ---- */
const optsFor=q=>q.opt==='cats'?R.LEAF_CATS.map(c=>[c,R.CATS[c].n]):q.opt==='allergens'?Object.entries(R.ALLERGENS):q.opt==='intol'?Object.entries(R.INTOL):q.opt==='diets'?Object.entries(R.DIETS):q.opt==='health'?Object.entries(R.HEALTH).map(([k,v])=>[k,v.n]):q.opt==='young'?['meat','poultry','seafood','legumes','eggs','dairy','spices'].map(c=>[c,R.CATS[c].n]):[];
W.screens.needs={render(p){const st=S(),m=st.members.find(x=>x.id===p.id);if(!m)return '<div class="scr">'+W.top('')+'</div>';const qs=E.questionsFor(m);let i=p.q!=null?p.q:Math.max(0,qs.findIndex(q=>!Array.isArray((m.answers||{})[q.c])));if(i>=qs.length)i=0;const q=qs[i];
 if(W.f.sel==null||W.f._q!==q.c){W.f._q=q.c;W.f.sel=((m.answers||{})[q.c]||[]).slice();}const sel=W.f.sel,nm=m.name;const age=E.ageLabel(m);
 const t=s=>e(String(s||'').replace(/\{name\}/g,nm));
 return '<div class="scr">'+W.top(nm+' · Question '+(i+1)+' of '+qs.length,{pct:Math.round((i+1)/qs.length*100)})+'<div class="scroll"><div class="wr">'+qs.map((x,j)=>'<button class="tg '+(j===i?'cur':Array.isArray((m.answers||{})[x.c])?'dn':'')+'" data-act="jump" data-i="'+j+'">'+x.tab+(Array.isArray((m.answers||{})[x.c])&&j!==i?' ✓':'')+'</button>').join('')+'</div>'+
 '<h1>'+t(q.p)+'</h1><p>'+(age?'Questions are matched to '+e(nm)+'’s age ('+e(age)+'). ':'')+'You can skip and return later.</p>'+
 (q.alert?'<div class="alert">'+W.i('warn')+'<span><b>Allergy:</b> '+t(q.alert.replace(/^Allergy: /,''))+'</span></div>':q.h?'<div class="alert info">'+W.i(q.consent?'lock':'shield')+'<span>'+t(q.h)+'</span></div>':'')+
 '<div class="g2">'+optsFor(q).map(([k,v])=>W.chip(v,sel.includes(k),'data-act="opt" data-k="'+k+'"')).join('')+'</div>'+W.chip('None of these',sel.includes('none'),'data-act="opt" data-k="none" style="width:100%"')+
 '</div><div class="foot"><button class="btn" data-act="save">Save &amp; Continue</button><button class="btn gh" data-act="skip">Skip for now</button></div></div>';},
 acts:{opt:el=>{const k=el.dataset.k,s=W.f.sel;if(k==='none'){W.f.sel=s.includes('none')?[]:['none'];}else{const x=s.filter(v=>v!=='none');x.includes(k)?x.splice(x.indexOf(k),1):x.push(k);W.f.sel=x;}W.render();},
  jump:el=>{const t=W.stack[W.stack.length-1];t.p=Object.assign({},t.p,{q:+el.dataset.i});W.f.sel=null;W.render(true);},
  save:()=>advance(true),skip:()=>advance(false)}};
function advance(save){const t=W.stack[W.stack.length-1],p=t.p,st=S(),m=st.members.find(x=>x.id===p.id),qs=E.questionsFor(m);let i=p.q!=null?p.q:Math.max(0,qs.findIndex(q=>!Array.isArray((m.answers||{})[q.c])));
 if(save){if(!W.f.sel.length){W.toast('Pick an option, or “None of these”.');return;}m.answers=m.answers||{};m.answers[qs[i].c]=W.f.sel.slice();W.save();}
 const next=qs.findIndex((q,j)=>j>i&&!Array.isArray(m.answers[q.c]));const nx=next>=0?next:(i+1<qs.length&&!save?i+1:-1);
 if(nx>=0){t.p=Object.assign({},p,{q:nx});W.f.sel=null;W.render(true);return;}
 if(E.progress(m).done)W.toast(m.name+'’s profile is complete');
 if(p.setup){const other=st.members.find(x=>!E.progress(x).done&&x.id!==m.id);if(other){W.go('needs',{id:other.id,setup:1},{replace:true});return;}finishStep('food_needs',p);}
 else W.back();}
/* ---- 5 Storage ---- */
W.screens.storage={render(p){const st=S(),k=E.kitchen(p.k||st.active);if(!k)return '';const locs=E.locsFor(k.id).filter(l=>!l.parent);const has=t=>locs.find(l=>l.type===t);const pantry=has('pantry');const shelves=pantry?st.locations.filter(l=>l.parent===pantry.id).length:0;
 return '<div class="scr">'+stepTop('kitchen',p,'Storage')+'<div class="scroll">'+(st.kitchens.length>1?'<div class="ksw">'+st.kitchens.map(x=>W.chip(x.name+' · '+x.country,x.id===k.id,'data-act="kk" data-id="'+x.id+'"','kc')).join('')+'</div>':'')+
 '<div><h1>Where do you keep food?</h1><p class="mt8">'+e(k.name)+' kitchen · '+(k.units==='us'?'U.S.':'metric')+' units</p></div><div class="g2">'+Object.entries(R.LOC_TYPES).map(([t,v])=>W.chip(v[0],!!has(t),'data-act="loc" data-t="'+t+'"')).join('')+'</div>'+
 (pantry?'<div class="card row sp"><div><h3>Pantry shelves</h3><p class="sub">Creates Shelf 1 to '+shelves+'</p></div>'+W.step(shelves,'shelf','data-k="'+k.id+'"')+'</div><p class="ok-ic row" style="font-weight:600">'+W.i('check')+'Your pantry is ready.</p>':'')+
 '</div><div class="foot"><button class="btn" data-act="cont">Continue</button></div></div>';},
 acts:{kk:el=>{const t=W.stack[W.stack.length-1];t.p=Object.assign({},t.p,{k:el.dataset.id});W.render();},
  loc:el=>{const t=W.stack[W.stack.length-1],st=S(),k=E.kitchen(t.p.k||st.active),type=el.dataset.t;const ex=st.locations.find(l=>l.k===k.id&&l.type===type&&!l.parent);
   if(ex){const ids=[ex.id].concat(st.locations.filter(l=>l.parent===ex.id).map(l=>l.id));const n=st.inv.filter(i=>ids.includes(i.loc)).length;if(n){W.toast('Move or use the '+n+' item'+(n>1?'s':'')+' stored there first.');return;}st.locations=st.locations.filter(l=>!ids.includes(l.id));}
   else st.locations.push({id:W.uid(),k:k.id,type,name:R.LOC_TYPES[type][0]});W.save();W.render();},
  shelf:el=>{const t=W.stack[W.stack.length-1],st=S(),k=E.kitchen(t.p.k||st.active);const pan=st.locations.find(l=>l.k===k.id&&l.type==='pantry'&&!l.parent);const sh=st.locations.filter(l=>l.parent===pan.id);
   if(+el.dataset.d>0){if(sh.length>=12)return;st.locations.push({id:W.uid(),k:k.id,type:'shelf',name:'Shelf '+(sh.length+1),parent:pan.id});}
   else{const last=sh[sh.length-1];if(!last)return;if(st.inv.some(i=>i.loc===last.id)){W.toast('Shelf '+sh.length+' still has food on it.');return;}st.locations=st.locations.filter(l=>l!==last);}W.save();W.render();},
  cont:()=>{const p=W.stack[W.stack.length-1].p;if(!E.locsFor(E.kitchen(p.k||S().active).id).length){W.toast('Pick at least one place you keep food.');return;}finishStep('kitchen',p);}}};
/* ---- 6 Appliances & tools ---- */
W.screens.items={render(p){const st=S(),k=E.kitchen(p.k||st.active);if(!k)return '';const tab=p.tab||'appliances';const cls=R.KCAT.find(c=>c[0]===tab);const have=st.kitems[k.id]||{};const doneT=(st.ui.kdone||{})[k.id]||[];
 const vis=it=>!it[3]||it[3].split(',').includes(k.country);
 return '<div class="scr">'+stepTop('appliances_tools',p,'Appliances & tools')+'<div class="scroll">'+(st.kitchens.length>1?'<div class="ksw">'+st.kitchens.map(x=>W.chip(x.name+' · '+x.country,x.id===k.id,'data-act="kk" data-id="'+x.id+'"','kc')).join('')+'</div>':'<h1>What’s in your kitchen?</h1>')+
 '<div class="tabs" role="tablist">'+R.KCAT.map(c=>'<button role="tab" class="'+(c[0]===tab?'on':doneT.includes(c[0])?'dn':'')+'" data-act="tab2" data-t="'+c[0]+'">'+c[1]+(doneT.includes(c[0])&&c[0]!==tab?' ✓':'')+'</button>').join('')+'</div>'+
 (tab==='appliances'?'<p class="sub">Appliances decide which meals you can make here. Counts are optional for everything else.</p>':'')+
 cls[2].map(g=>{const its=g[1].filter(vis);if(!its.length)return '';return '<div class="gl">'+e(g[0])+'</div>'+its.map(it=>{const n=have[it[0]]||0;return '<div class="ki"><div class="grow row" style="gap:8px;flex-wrap:wrap"><b>'+e(it[1])+'</b><span class="tag">'+e(it[3]?'Common in '+(R.COUNTRY_ADJ[k.country]||k.country):it[2])+'</span></div>'+W.step(n,'q','data-c="'+it[0]+'"')+'</div>';}).join('');}).join('')+
 '</div><div class="foot"><button class="btn" data-act="savecls">Save '+e(cls[1].toLowerCase())+'</button>'+(p.setup?'<button class="btn gh" data-act="done">I’m done with this kitchen</button>':'')+'</div></div>';},
 acts:{kk:el=>{const t=W.stack[W.stack.length-1];t.p=Object.assign({},t.p,{k:el.dataset.id});W.render(true);},
  tab2:el=>{const t=W.stack[W.stack.length-1];t.p=Object.assign({},t.p,{tab:el.dataset.t});W.render(true);},
  q:el=>{const t=W.stack[W.stack.length-1],st=S(),k=E.kitchen(t.p.k||st.active);const m=st.kitems[k.id]=st.kitems[k.id]||{};const c=el.dataset.c;m[c]=Math.max(0,(m[c]||0)+(+el.dataset.d));if(!m[c])delete m[c];W.save();W.render();},
  savecls:()=>{const t=W.stack[W.stack.length-1],st=S(),k=E.kitchen(t.p.k||st.active);const tab=t.p.tab||'appliances';st.ui.kdone=st.ui.kdone||{};const d=st.ui.kdone[k.id]=st.ui.kdone[k.id]||[];if(!d.includes(tab))d.push(tab);W.save();
   const i=R.KCAT.findIndex(c=>c[0]===tab);W.toast(R.KCAT[i][1]+' saved');if(i+1<R.KCAT.length){t.p=Object.assign({},t.p,{tab:R.KCAT[i+1][0]});W.render(true);}else finishStep('appliances_tools',t.p);},
  done:()=>finishStep('appliances_tools',W.stack[W.stack.length-1].p)}};
/* ---- 8 Start meal matching ---- */
W.screens.finish={render(){const st=S();const items=st.inv.length,mem=st.members.length;const r=E.match(st.active,E.membersIn(st.active).map(m=>m.id)).filter(x=>!x.blocked).length;
 return '<div class="scr">'+W.top('Step 8 of 8',{pct:100})+'<div class="scroll center" style="justify-content:center"><img src="'+W.LOGO+'" width="140" height="140" alt="" style="border-radius:22%">'+
 '<h1>You’re ready to cook smarter</h1><p>We match meals to who is eating, their food needs, what you have and the tools in your kitchen.</p><div class="g4" style="width:100%;grid-template-columns:repeat(3,1fr)"><div class="stat"><b>'+mem+'</b><span>Profiles</span></div><div class="stat"><b>'+items+'</b><span>Food items</span></div><div class="stat"><b>'+r+'</b><span>Meals fit</span></div></div>'+
 (items?'':'<div class="alert warn">'+W.i('warn')+'<span>Add a few food items so suggestions can use what you have.</span></div>')+'</div><div class="foot"><button class="btn y" data-act="go">See Meal Suggestions</button>'+(items?'':'<button class="btn o" data-act="add">Add Food</button>')+'</div></div>';},
 acts:{go:()=>{W.markStep('meal_matching');W.go('meals',{},{root:true});},add:()=>W.go('addfood',{setup:1})}};
return true;});
