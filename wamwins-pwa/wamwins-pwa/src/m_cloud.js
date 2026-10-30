/* Cloud: Supabase Auth (GoTrue) + PostgREST sync against the wamwins-db schema.
   Loaded only when config.js sets supabaseUrl + supabaseAnonKey. The device copy stays the offline cache. */
W.def('cloud', function(W){
const C=W.CONFIG||{},BASE=String(C.supabaseUrl||'').replace(/\/+$/,''),KEY=C.supabaseAnonKey||'',LSK='wamwins.v1.cloud';
const R=W.use('ref'),E=W.use('engine');
let st=(()=>{try{return JSON.parse(localStorage.getItem(LSK))||{};}catch(_){return {};}})();
const keep=()=>{try{localStorage.setItem(LSK,JSON.stringify(st));}catch(_){}};
const here=()=>location.origin+location.pathname;
const H=s=>{let h=5381;for(let i=0;i<s.length;i++)h=((h<<5)+h+s.charCodeAt(i))|0;return (h>>>0).toString(36);};
const iso=t=>new Date(t||Date.now()).toISOString();
const nn=v=>v===''||v==null?null:v;
function fail(j,status){const e=new Error(j&&(j.msg||j.error_description||j.message||j.error)||('Request failed ('+status+')'));e.code=j&&(j.error_code||j.code);e.status=status;return e;}
/* ---------------- auth ---------------- */
async function auth(path,body,method,tok){const r=await fetch(BASE+'/auth/v1/'+path,{method:method||'POST',headers:Object.assign({apikey:KEY,'Content-Type':'application/json'},tok?{Authorization:'Bearer '+tok}:{}),body:body?JSON.stringify(body):undefined});
 const t=await r.text();let j={};try{j=t?JSON.parse(t):{};}catch(_){}if(!r.ok)throw fail(j,r.status);return j;}
function setSession(j,user){st.sess={access:j.access_token,refresh:j.refresh_token,exp:Date.now()+((+j.expires_in||3600)*1000),user:user||j.user};keep();}
async function token(){if(!st.sess)throw fail({message:'Not signed in'},401);if(Date.now()>st.sess.exp-60000){const j=await auth('token?grant_type=refresh_token',{refresh_token:st.sess.refresh});setSession(j,j.user||st.sess.user);}return st.sess.access;}
const uid=()=>st.sess&&st.sess.user&&st.sess.user.id;
/* ---------------- REST ---------------- */
async function rest(method,schema,path,body,prefer,retried){const tok=await token();const h={apikey:KEY,Authorization:'Bearer '+tok,'Content-Type':'application/json'};h[method==='GET'?'Accept-Profile':'Content-Profile']=schema;if(prefer)h.Prefer=prefer;
 const r=await fetch(BASE+'/rest/v1/'+path,{method,headers:h,body:body!==undefined?JSON.stringify(body):undefined});
 if(r.status===401&&!retried){st.sess.exp=0;return rest(method,schema,path,body,prefer,true);}
 const t=await r.text();let j=null;try{j=t?JSON.parse(t):null;}catch(_){}if(!r.ok)throw fail(j,r.status);return j;}
const get=(s,t,q)=>rest('GET',s,t+'?'+q);
const rpc=(s,fn,args)=>rest('POST',s,'rpc/'+fn,args||{});
async function upsert(s,t,rows,conflict){for(let i=0;i<rows.length;i+=400)await rest('POST',s,t+(conflict?'?on_conflict='+conflict:''),rows.slice(i,i+400),'resolution=merge-duplicates,return=minimal');}
async function insert(s,t,rows){for(let i=0;i<rows.length;i+=400)await rest('POST',s,t,rows.slice(i,i+400),'return=minimal');}
async function softDel(s,t,ids){for(let i=0;i<ids.length;i+=100)await rest('PATCH',s,t+'?id=in.('+ids.slice(i,i+100).join(',')+')',{deleted_at:iso()},'return=minimal');}
/* ---------------- master data maps (codes <-> ids) ---------------- */
let REF=null;
async function loadRef(){if(REF)return REF;const g=(s,t,c)=>get(s,t,'select='+c);
 const [units,foods,cats,locs,kit,als,qs,opts,recs,goals,docs]=await Promise.all([g('ref','units','id,code,to_base'),get('ref','food_items','household_id=is.null&code=not.is.null&select=id,code'),g('ref','food_categories','id,code'),g('ref','location_types','id,code'),g('ref','kitchen_item_types','id,code'),g('ref','allergens','id,code'),g('ref','profile_questions','id,code'),g('ref','profile_question_options','id,code,question_id'),get('ref','recipes','code=not.is.null&select=id,code'),g('ref','help_goals','id,code'),g('core','consent_documents','id,kind,version')]);
 const m=a=>{const o={id:{},code:{}};for(const r of a){o.id[r.code]=r.id;o.code[r.id]=r.code;}return o;};
 REF={unit:m(units),toBase:Object.fromEntries(units.map(u=>[u.id,+u.to_base])),food:m(foods),cat:m(cats),loc:m(locs),kit:m(kit),al:m(als),q:m(qs),opt:Object.fromEntries(opts.map(o=>[o.id,o])),rec:m(recs),goal:m(goals),doc:Object.fromEntries(docs.map(d=>[d.kind,d.id])),docKind:Object.fromEntries(docs.map(d=>[d.id,d.kind]))};return REF;}
const baseUnit=dim=>dim==='mass'?'g':dim==='volume'?'ml':'each';
/* ---------------- local state -> rows ---------------- */
function foodDb(code){if(R.FOODS[code])return REF.food.id[code]||null;const c=(st.cf||{})[code];return c||null;}
function build(S){const hid=st.hh,me=S.members.find(m=>m.self),out={};
 out.kitchens=S.kitchens.map((k,i)=>({id:k.id,household_id:hid,name:k.name,is_primary:i===0,country_code:k.country||null,region_code:nn(k.region),timezone:nn(k.tz),measurement_system:k.units||'us',locale:k.locale||'en'}));
 out.members=S.members.map(m=>({id:m.id,household_id:hid,preferred_name:m.name,relationship:m.self?'self':(m.rel||'other'),age_range:nn(m.band),age_years:m.age===''||m.age==null?null:+m.age,user_id:m.self?uid():null,is_account_holder:!!m.self}));
 out.home=Object.fromEntries(S.members.map(m=>[m.id,m.k||'']));
 out.about=JSON.stringify([S.about.name||(me&&me.name)||'',S.about.role||'',(S.about.goals||[]).slice().sort()]);
 out.locations=S.locations.map((l,i)=>({id:l.id,household_id:hid,kitchen_id:l.k,parent_id:l.parent||null,location_type_id:REF.loc.id[l.type]||REF.loc.id.other,name:l.name,sort_order:i}));
 st.ki=st.ki||{};out.kitems=[];for(const k in S.kitems){if(!S.kitchens.some(x=>x.id===k))continue;for(const code in S.kitems[k]){const q=S.kitems[k][code];const t=REF.kit.id[code];if(!(q>0)||!t)continue;const key=k+'|'+code;const id=st.ki[key]||(st.ki[key]=W.uid());out.kitems.push({id,household_id:hid,kitchen_id:k,item_type_id:t,quantity:q});}}
 st.cf=st.cf||{};out.cfoods=(S.foods||[]).map(f=>{const id=st.cf[f.id]||(st.cf[f.id]=W.uid());return {id,household_id:hid,code:f.id,name:f.name,category_id:REF.cat.id[f.cat]||null,default_unit_id:REF.unit.id[(f.u||{}).us||'each']||null,is_system:false,_al:(f.al||[]).slice().sort().join(',')};});
 out.inv=S.inv.filter(l=>foodDb(l.food)).map(l=>({id:l.id,household_id:hid,kitchen_id:l.k,food_item_id:foodDb(l.food),location_id:l.loc||null,display_unit_id:REF.unit.id[l.unit],brand:nn(l.brand),best_by_date:nn(l.bestBy),expiration_date:nn(l.exp),opened_on:nn(l.opened),pack_count:+l.packs>0?Math.round(+l.packs):null,pack_label:nn(l.pkg),initial_qty:l.init!=null?+l.init:null,low_alert:l.low==null||l.low===''?null:+l.low,status:'active'}));
 out.shop=S.shop.map(s=>({id:s.id,household_id:hid,list_id:st.list,food_item_id:s.food?foodDb(s.food):null,custom_name:s.name,status:s.done?'bought':'open',source:/low|used up/i.test(s.note||'')?'low_stock':/^For /.test(s.note||'')?'recipe':'manual',kitchen_id:s.k||null,note:nn(s.note)}));
 out.meals=S.meals.map(m=>{const r=R.RECIPES.find(x=>x.id===m.r);return {id:m.id,household_id:hid,recipe_id:REF.rec.id[m.r]||null,title:r?r.title:(m.title||'Meal'),cooked_at:iso(m.at),servings:m.serv||null,kitchen_id:m.k||null,used:m.used||[]};});
 out.who=Object.fromEntries(S.meals.map(m=>[m.id,(m.who||[]).filter(id=>S.members.some(x=>x.id===id))]));
 out.setup=Object.entries(S.setup||{}).filter(([c,v])=>['done','skipped','in_progress'].includes(v)&&R.STEPS.some(s=>s[0]===c)).map(([c,v])=>({household_id:hid,step_code:c,status:v}));
 return out;}
/* ---------------- push ---------------- */
let busy=null,again=false,timer=null;
async function diffUpsert(name,schema,table,rows,conflict,keyOf){st.sent=st.sent||{};const prev=st.sent[name]||{},next={},changed=[];keyOf=keyOf||(r=>r.id);
 for(const r of rows){const k=keyOf(r);const h=H(JSON.stringify(r));next[k]=h;if(prev[k]!==h)changed.push(r);}
 const clean=changed.map(r=>{const o={};for(const x in r)if(x[0]!=='_')o[x]=r[x];return o;});
 if(clean.length)await upsert(schema,table,clean,conflict);
 const gone=Object.keys(prev).filter(k=>!(k in next));st.sent[name]=next;keep();return {changed,gone};}
function remap(pairs){let j=JSON.stringify(W.S);for(const [a,b] of pairs)if(a&&b&&a!==b)j=j.split(a).join(b);W.S=JSON.parse(j);W.saveLocal();}
async function createHousehold(){const S=W.S,k0=S.kitchens[0]||{};
 const hid=await rpc('core','create_household',{p_user:uid(),p_name:S.household.name,p_country:S.household.country||'US',p_region:nn(S.household.region),p_timezone:nn(k0.tz),p_people:S.household.people||null});
 const [k]=await get('hh','kitchens','household_id=eq.'+hid+'&is_primary=eq.true&deleted_at=is.null&select=id');
 const [me]=await get('hh','family_members','household_id=eq.'+hid+'&user_id=eq.'+uid()+'&deleted_at=is.null&select=id');
 const self=S.members.find(m=>m.self);remap([[S.household.id,hid],[k0.id,k&&k.id],[self&&self.id,me&&me.id]]);
 st.hh=hid;st.sent={};st.qty={};st.ans={};st.list=null;keep();}
async function pushNow(){const S0=W.S;if(!st.sess||!S0.household)return;await loadRef();if(!st.hh)await createHousehold();
 const S=W.S,hid=st.hh,b=build(S);st.qty=st.qty||{};st.ans=st.ans||{};
 /* household */
 const hrow={name:S.household.name,people_count:S.household.people||null,country_code:S.household.country||'US',region_code:nn(S.household.region),measurement_system:(S.kitchens[0]||{}).units||'us'};
 if((st.sent||{}).hh!==H(JSON.stringify(hrow))){await rest('PATCH','core','households?id=eq.'+hid,hrow,'return=minimal');st.sent=st.sent||{};st.sent.hh=H(JSON.stringify(hrow));keep();}
 /* kitchens: deletions first so the primary kitchen can move */
 const kPrev=Object.keys((st.sent||{}).kitchens||{}).filter(id=>!b.kitchens.some(k=>k.id===id));if(kPrev.length){await softDel('hh','kitchens',kPrev);}
 await diffUpsert('kitchens','hh','kitchens',b.kitchens,'id');
 const mem=await diffUpsert('members','hh','family_members',b.members,'id');
 /* home kitchen per member */
 st.home=st.home||{};for(const m of S.members){if(st.home[m.id]===b.home[m.id]||!b.home[m.id])continue;await rest('DELETE','hh','member_kitchens?member_id=eq.'+m.id,undefined,'return=minimal');await insert('hh','member_kitchens',[{household_id:hid,member_id:m.id,kitchen_id:b.home[m.id],is_home:true}]);st.home[m.id]=b.home[m.id];keep();}
 /* about you */
 if(st.about!==H(b.about)&&S.members.some(m=>m.self)){const a=JSON.parse(b.about);if(a[0]){await rpc('core','save_about_you',{p_household:hid,p_display_name:a[0],p_role:a[1]||null,p_goals:a[2]});st.about=H(b.about);keep();}}
 /* food needs answers */
 for(const m of S.members){const a=m.answers||{};st.ans[m.id]=st.ans[m.id]||{};for(const qc in a){if(!Array.isArray(a[qc])||!a[qc].length)continue;const v=a[qc].slice().sort().join(',');if(st.ans[m.id][qc]===v)continue;
  try{await rpc('health','save_answers',{p_household:hid,p_member:m.id,p_question:qc,p_options:a[qc]});st.ans[m.id][qc]=v;keep();}catch(e){if(/question_not_applicable|unknown_question/.test(e.message)){st.ans[m.id][qc]=v;keep();}else throw e;}}}
 const loc=await diffUpsert('locations','hh','locations',b.locations,'id');
 const ki=await diffUpsert('kitems','hh','kitchen_items',b.kitems,'id');
 const cf=await diffUpsert('cfoods','ref','food_items',b.cfoods,'id');
 for(const f of cf.changed){await rest('DELETE','ref','food_item_allergens?food_item_id=eq.'+f.id,undefined,'return=minimal');const rows=(f._al?f._al.split(','):[]).map(c=>REF.al.id[c]).filter(Boolean).map(id=>({food_item_id:f.id,allergen_id:id,presence:'contains'}));if(rows.length)await insert('ref','food_item_allergens',rows);}
 const inv=await diffUpsert('inv','hh','inventory_items',b.inv,'id');
 /* ledger: one transaction per change in amount (append-only) */
 const tx=[];const now=new Set(b.inv.map(r=>r.id));
 for(const l of S.inv){if(!now.has(l.id))continue;const dim=E.unitDim(l.unit);const base=Math.round(E.toBase(l.qty,l.unit)*1e4)/1e4;const known=st.qty[l.id];const d=Math.round((base-(known||0))*1e4)/1e4;if(Math.abs(d)<1e-4)continue;
  tx.push({household_id:hid,inventory_item_id:l.id,kind:d>0?(known==null?'add':'adjust'):'use',quantity:Math.abs(d),unit_id:REF.unit.id[baseUnit(dim)],note:'app'});}
 for(const id of Object.keys(st.qty)){if(now.has(id))continue;const known=st.qty[id];if(known>0){const last=S.tx.find(t=>t.lot===id);tx.push({household_id:hid,inventory_item_id:id,kind:last&&/waste|delete/.test(last.kind)?'discard':'consume',quantity:known,unit_id:REF.unit.id[baseUnit(last?last.dim:'count')]||REF.unit.id.each,note:'app'});}}
 if(tx.length){await insert('hh','inventory_transactions',tx);}
 for(const l of S.inv)if(now.has(l.id))st.qty[l.id]=Math.round(E.toBase(l.qty,l.unit)*1e4)/1e4;for(const id of Object.keys(st.qty))if(!now.has(id))delete st.qty[id];keep();
 /* shopping list */
 if(!st.list){const ls=await get('hh','shopping_lists','household_id=eq.'+hid+'&deleted_at=is.null&select=id&order=created_at&limit=1');st.list=ls[0]?ls[0].id:W.uid();if(!ls[0])await insert('hh','shopping_lists',[{id:st.list,household_id:hid,name:'Grocery List'}]);keep();b.shop.forEach(s=>s.list_id=st.list);}
 const sh=await diffUpsert('shop','hh','shopping_list_items',b.shop,'id');
 const ml=await diffUpsert('meals','hh','meal_logs',b.meals,'id');
 const parts=ml.changed.flatMap(m=>(b.who[m.id]||[]).map(mid=>({household_id:hid,meal_log_id:m.id,member_id:mid})));if(parts.length)await upsert('hh','meal_log_participants',parts,'meal_log_id,member_id');
 await diffUpsert('setup','core','setup_progress',b.setup,'household_id,step_code',r=>r.step_code);
 /* consent evidence (append-only) */
 const log=S.consent.log||[];st.cons=st.cons||0;if(log.length>st.cons){const rows=log.slice(st.cons).map(c=>({user_id:uid(),household_id:hid,document_id:REF.doc[c.type==='health_data'?'health_data':'privacy'],granted:!!c.value,granted_at:iso(c.at),platform:'web'})).filter(r=>r.document_id);if(rows.length)await insert('core','consent_records',rows);st.cons=log.length;keep();}
 /* removals (soft delete keeps history) */
 if(ml.gone.length)await softDel('hh','meal_logs',ml.gone);if(sh.gone.length)await softDel('hh','shopping_list_items',sh.gone);
 if(inv.gone.length)await softDel('hh','inventory_items',inv.gone);if(ki.gone.length)await softDel('hh','kitchen_items',ki.gone);
 if(cf.gone.length)await softDel('ref','food_items',cf.gone);if(loc.gone.length)await softDel('hh','locations',loc.gone);
 if(mem.gone.length){await softDel('hh','family_members',mem.gone);for(const id of mem.gone){delete st.home[id];delete st.ans[id];}}
 st.dirty=false;st.lastPush=Date.now();keep();}
async function push(){if(busy){again=true;return busy;}busy=(async()=>{try{await pushNow();setStatus('ok');}catch(e){st.dirty=true;keep();setStatus('err',e);}finally{busy=null;if(again){again=false;push();}}})();return busy;}
function schedule(){if(!st.sess)return;st.dirty=true;keep();clearTimeout(timer);timer=setTimeout(push,1500);}
let warned=false;function setStatus(s,e){W.syncState=s;if(s==='err'&&!warned&&e&&e.status!==undefined){warned=true;W.toast&&W.toast(navigator.onLine?'Saved on this device. Sync failed: '+e.message:'Offline. Changes are saved on this device and sync when you reconnect.');}if(s==='ok')warned=false;}
/* ---------------- pull: server rows -> app state ---------------- */
async function pull(){await loadRef();const u=uid();
 const ms=await get('core','household_memberships','user_id=eq.'+u+'&status=eq.active&deleted_at=is.null&select=household_id,household_role&limit=1');
 const [usr]=await get('core','users','id=eq.'+u+'&select=first_name,last_name,email,email_verified_at');
 if(!ms.length)return {account:usr,household:null};
 const hid=ms[0].household_id,q='household_id=eq.'+hid+'&deleted_at=is.null';
 const [hh,kit,mem,mk,ans,locs,kis,inv,cfs,ls,items,meals,parts,setup,goals,cons]=await Promise.all([
  get('core','households','id=eq.'+hid+'&select=*'),get('hh','kitchens',q+'&select=*&order=is_primary.desc,created_at'),get('hh','family_members',q+'&select=*&order=created_at'),
  get('hh','member_kitchens',q+'&is_home=eq.true&select=member_id,kitchen_id'),get('health','member_profile_answers',q+'&select=member_id,question_id,option_id'),
  get('hh','locations',q+'&select=*&order=sort_order'),get('hh','kitchen_items',q+'&select=id,kitchen_id,item_type_id,quantity'),get('hh','inventory_items',q+'&status=eq.active&select=*&order=created_at'),
  get('ref','food_items','household_id=eq.'+hid+'&deleted_at=is.null&select=id,code,name,category_id,default_unit_id'),get('hh','shopping_lists',q+'&select=id&order=created_at&limit=1'),
  get('hh','shopping_list_items',q+'&select=*&order=created_at.desc'),get('hh','meal_logs',q+'&select=*&order=cooked_at.desc&limit=300'),get('hh','meal_log_participants',q+'&select=meal_log_id,member_id'),
  get('core','setup_progress','household_id=eq.'+hid+'&select=step_code,status'),get('core','membership_goals','household_id=eq.'+hid+'&user_id=eq.'+u+'&deleted_at=is.null&select=goal_id'),
  get('core','consent_records','user_id=eq.'+u+'&select=document_id,granted,granted_at&order=granted_at')]);
 const cal=cfs.length?await get('ref','food_item_allergens','food_item_id=in.('+cfs.map(f=>f.id).join(',')+')&select=food_item_id,allergen_id'):[];
 const h=hh[0]||{},S=W.blank();st.cf={};
 S.household={id:hid,name:h.name,people:h.people_count||1,country:h.country_code||'US',region:h.region_code||'',created:Date.parse(h.created_at)||Date.now()};
 S.kitchens=kit.map(k=>{const c=R.COUNTRIES[k.country_code]||[];return {id:k.id,name:k.name,country:k.country_code||h.country_code||'US',region:k.region_code||'',units:k.measurement_system||c[1]||'us',locale:String(k.locale||c[2]||'en').split('-')[0],tz:k.timezone||c[3]||''};});
 const home=Object.fromEntries(mk.map(x=>[x.member_id,x.kitchen_id]));const prim=(S.kitchens[0]||{}).id;
 const answers={};for(const a of ans){const o=REF.opt[a.option_id];if(!o)continue;const qc=REF.q.code[o.question_id];(answers[a.member_id]=answers[a.member_id]||{})[qc]=((answers[a.member_id]||{})[qc]||[]).concat(o.code);}
 S.members=mem.map(m=>({id:m.id,self:m.relationship==='self'||m.user_id===u,name:m.preferred_name,rel:m.relationship,role:'',band:m.age_range||'',age:m.age_years==null?'':m.age_years,k:home[m.id]||prim,answers:answers[m.id]||{}}));
 S.about={name:(S.members.find(m=>m.self)||{}).name||(usr&&usr.first_name)||'',role:ms[0].household_role||'',goals:goals.map(g=>REF.goal.code[g.goal_id]).filter(Boolean)};
 S.locations=locs.map(l=>({id:l.id,k:l.kitchen_id,type:REF.loc.code[l.location_type_id]||'other',name:l.name,parent:l.parent_id||undefined}));
 st.ki={};for(const x of kis){const c=REF.kit.code[x.item_type_id];if(!c||!x.kitchen_id)continue;(S.kitems[x.kitchen_id]=S.kitems[x.kitchen_id]||{})[c]=x.quantity;st.ki[x.kitchen_id+'|'+c]=x.id;}
 S.foods=cfs.map(f=>{const code=f.code||('c_'+f.id.slice(0,8));st.cf[code]=f.id;const u2=REF.unit.code[f.default_unit_id]||'each';return {id:code,name:f.name,cat:REF.cat.code[f.category_id]||'pantry',al:cal.filter(a=>a.food_item_id===f.id).map(a=>REF.al.code[a.allergen_id]).filter(Boolean),alias:'',u:{us:u2,metric:u2},life:14,loc:'pantry',custom:true};});
 const fcode=id=>REF.food.code[id]||Object.keys(st.cf).find(c=>st.cf[c]===id);
 st.qty={};S.inv=inv.filter(i=>fcode(i.food_item_id)).map(i=>{const unit=REF.unit.code[i.display_unit_id]||'each';const qty=Math.round((+i.qty_base/(REF.toBase[i.display_unit_id]||1))*1e4)/1e4;st.qty[i.id]=Math.round(+i.qty_base*1e4)/1e4;
  return {id:i.id,k:i.kitchen_id||prim,food:fcode(i.food_item_id),qty,unit,loc:i.location_id||'',init:i.initial_qty!=null?+i.initial_qty:qty,low:i.low_alert!=null?+i.low_alert:null,pkg:i.pack_label||'',packs:i.pack_count||'',bestBy:i.best_by_date||'',exp:i.expiration_date||'',brand:i.brand||'',opened:i.opened_on||'',added:Date.parse(i.created_at)||Date.now()};});
 st.list=ls[0]?ls[0].id:null;
 S.shop=items.filter(s=>s.status!=='removed').map(s=>({id:s.id,k:s.kitchen_id||prim,food:s.food_item_id?(fcode(s.food_item_id)||''):'',name:s.custom_name||(s.food_item_id?E.food(fcode(s.food_item_id)).name:'Item'),note:s.note||'',done:s.status==='bought',at:Date.parse(s.created_at)||Date.now()}));
 S.meals=meals.map(m=>({id:m.id,r:REF.rec.code[m.recipe_id]||'',title:m.title,k:m.kitchen_id||prim,at:Date.parse(m.cooked_at),serv:+m.servings||1,who:parts.filter(p=>p.meal_log_id===m.id).map(p=>p.member_id),used:m.used||[]}));
 for(const s of setup)if(s.status!=='pending')S.setup[s.step_code]=s.status;
 S.consent={privacy:null,health:null,log:[]};for(const c of cons){const kind=REF.docKind[c.document_id];if(!kind)continue;const at=Date.parse(c.granted_at);S.consent.log.push({type:kind==='health_data'?'health_data':'privacy_notice',value:c.granted,at});if(kind==='privacy'&&c.granted&&!S.consent.privacy)S.consent.privacy=at;if(kind==='health_data')S.consent.health=c.granted;}
 st.cons=S.consent.log.length;
 return {account:usr,state:S,hid};}
function adopt(res){const prev=W.S;const S=res.state||W.blank();const a=res.account||{};
 S.account={first:a.first_name||(prev.account||{}).first||'',last:a.last_name||'',email:a.email||(st.sess.user||{}).email,verified:true,cloud:true,created:(prev.account||{}).created||Date.now()};
 S.signedIn=true;S.ui=Object.assign({},prev.ui||{});if(!res.state){S.consent=prev.account&&prev.account.email===S.account.email?prev.consent:S.consent;S.about.name=S.account.first;}
 if(S.kitchens.length&&!S.kitchens.some(k=>k.id===prev.active))S.active=S.kitchens[0].id;else S.active=prev.active&&S.kitchens.some(k=>k.id===prev.active)?prev.active:(S.kitchens[0]||{}).id||null;
 W.S=S;W.saveLocal();
 if(res.state){st.hh=res.hid;st.dirty=false;REF&&(()=>{const b=build(S);st.sent={hh:H(JSON.stringify({name:S.household.name,people_count:S.household.people||null,country_code:S.household.country||'US',region_code:nn(S.household.region),measurement_system:(S.kitchens[0]||{}).units||'us'}))};
  const hs=(rows,key)=>Object.fromEntries(rows.map(r=>[(key||(x=>x.id))(r),H(JSON.stringify(r))]));st.sent.kitchens=hs(b.kitchens);st.sent.members=hs(b.members);st.sent.locations=hs(b.locations);st.sent.kitems=hs(b.kitems);st.sent.cfoods=hs(b.cfoods);st.sent.inv=hs(b.inv);st.sent.shop=hs(b.shop);st.sent.meals=hs(b.meals);st.sent.setup=hs(b.setup,r=>r.step_code);
  st.home=Object.assign({},b.home);st.about=H(b.about);st.ans={};for(const m of S.members){st.ans[m.id]={};for(const qc in m.answers||{})st.ans[m.id][qc]=m.answers[qc].slice().sort().join(',');}})();}
 else{st.hh=null;st.sent={};st.qty={};st.ans={};st.home={};st.list=null;}
 st.lastPull=Date.now();keep();}
/* ---------------- public API ---------------- */
const api={
 on:!!(BASE&&KEY),user:()=>st.sess&&st.sess.user,
 async signUp(o){const j=await auth('signup?redirect_to='+encodeURIComponent(here()),{email:o.email,password:o.pw,data:{first_name:o.first,last_name:o.last||''}});if(j.access_token){setSession(j);return {session:true};}return {confirm:true};},
 resend:email=>auth('resend',{type:'signup',email,options:{email_redirect_to:here()}}),
 async signIn(email,pw){const j=await auth('token?grant_type=password',{email,password:pw});setSession(j);await api.sync(true);},
 recover:email=>auth('recover?redirect_to='+encodeURIComponent(here()),{email}),
 async setPassword(pw){await auth('user',{password:pw},'PUT',await token());},
 oauth(p){location.href=BASE+'/auth/v1/authorize?provider='+encodeURIComponent(p)+'&redirect_to='+encodeURIComponent(here());},
 async signOut(){try{if(st.sess)await auth('logout',null,'POST',st.sess.access);}catch(_){}st={};keep();},
 /* sign-in / app start: push unsynced changes first, then take the server copy */
 async sync(fresh){if(!st.sess)return;if(st.dirty&&!fresh&&st.hh&&W.S.household)await pushNow();const res=await pull();const L=W.S;
  const same=L.account&&L.account.email&&res.account&&String(L.account.email).toLowerCase()===String(res.account.email).toLowerCase();
  if(!res.state&&L.household&&same){/* first sign-in on the device that set up before signing in: upload it */L.account.cloud=true;L.signedIn=true;W.saveLocal();st.hh=null;st.sent={};st.qty={};st.ans={};st.home={};keep();await pushNow();return;}
  adopt(res);},
 async start(){const hs=new URLSearchParams(location.hash.slice(1));let type=null;
  if(hs.get('access_token')){const tok=hs.get('access_token');try{const user=await auth('user',null,'GET',tok);setSession({access_token:tok,refresh_token:hs.get('refresh_token'),expires_in:hs.get('expires_in')},user);type=hs.get('type')||'oauth';}catch(_){}try{history.replaceState(null,'',location.pathname+location.search);}catch(_){}}
  else if(hs.get('error_description')){W.toast(hs.get('error_description').replace(/\+/g,' '));try{history.replaceState(null,'',location.pathname+location.search);}catch(_){}}
  if(st.sess){try{await api.sync(false);}catch(e){setStatus('err',e);}}
  return type;},
 schedule,push,
 async deleteHousehold(){if(st.hh)await rpc('core','delete_household',{p_household:st.hh});st.hh=null;st.sent={};st.qty={};st.ans={};st.home={};st.list=null;keep();},
 state:()=>({signedIn:!!st.sess,dirty:!!st.dirty,last:st.lastPush||st.lastPull||0})};
W.onSaved=()=>{if(st.sess)schedule();};
window.addEventListener('online',()=>{if(st.dirty)push();});
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&st.sess&&!st.dirty&&Date.now()-(st.lastPull||0)>60000&&W.S.household)api.sync(false).then(()=>W.render()).catch(()=>{});});
return api;});
