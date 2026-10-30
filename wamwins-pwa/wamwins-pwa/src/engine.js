/* Domain engine: units, inventory, member constraints, matching (port of match.match_recipes). */
W.def('engine', function(W){
const R=W.use('ref'), DAY=864e5;
const E={};
E.today=()=>{const d=new Date();d.setHours(0,0,0,0);return d;};
E.iso=d=>{const x=new Date(d);return x.getFullYear()+'-'+String(x.getMonth()+1).padStart(2,'0')+'-'+String(x.getDate()).padStart(2,'0');};
E.parse=s=>{if(!s)return null;const [y,m,d]=s.split('-').map(Number);return new Date(y,m-1,d);};
E.addDays=(d,n)=>new Date(+d+n*DAY);
E.unitDim=u=>(R.UNITS[u]||R.UNITS.each)[0];
E.toBase=(q,u)=>(+q||0)*(R.UNITS[u]||R.UNITS.each)[1];
E.fromBase=(b,u)=>b/(R.UNITS[u]||R.UNITS.each)[1];
E.sym=u=>(R.UNITS[u]||R.UNITS.each)[2];
E.num=n=>{n=+n;if(!isFinite(n))return '0';const r=Math.abs(n)>=100?Math.round(n):Math.round(n*100)/100;return String(r);};
E.fmt=(q,u)=>E.num(q)+' '+E.sym(u);
/* best display of a base quantity in a kitchen's unit system */
E.pretty=(base,dim,sys)=>{if(dim==='count')return E.fmt(base,'each');
 if(dim==='mass'){if(sys==='us')return base>=453.6?E.fmt(base/453.59237,'lb'):E.fmt(base/28.3495,'oz');return base>=1000?E.fmt(base/1000,'kg'):E.fmt(base,'g');}
 if(sys==='us')return base>=946?E.fmt(base/236.588,'cup'):E.fmt(base/29.5735,'fl_oz');return base>=1000?E.fmt(base/1000,'l'):E.fmt(base,'ml');};
E.kitchen=id=>W.S.kitchens.find(k=>k.id===(id||W.S.active))||W.S.kitchens[0];
E.sys=k=>(k||E.kitchen()||{}).units||'us';
E.food=id=>R.FOODS[id]||(W.S.foods||[]).find(f=>f.id===id)||{id,name:'Unknown item',cat:'pantry',al:[],u:{us:'each',metric:'each'},life:7};
E.foodName=lot=>lot.name||E.food(lot.food).name;
E.catAnc=c=>{const a=[];while(c){a.push(c);c=(R.CATS[c]||{}).p;}return a;};
/* alias search: local names work */
const norm=s=>String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9 ]/g,' ').replace(/\s+/g,' ').trim();
E.norm=norm;
E.search=q=>{q=norm(q);if(!q)return [];const out=[];const all=Object.values(R.FOODS).concat(W.S.foods||[]);
 for(const f of all){const n=norm(f.name);const al=norm(f.alias);let s=0;
  if(n===q)s=100;else if(n.startsWith(q))s=80;else if((' '+al+' ').includes(' '+q+' '))s=90;else if(n.includes(q))s=60;else if(al.includes(q))s=50;
  if(s)out.push([s,f]);}
 return out.sort((a,b)=>b[0]-a[0]).slice(0,6).map(x=>x[1]);};
E.exact=q=>{q=norm(q);if(!q)return null;const all=Object.values(R.FOODS).concat(W.S.foods||[]);
 return all.find(f=>norm(f.name)===q||(' '+norm(f.alias)+' ').includes(' '+q+' ')||norm(f.name).replace(/\(.*\)/,'').trim()===q)||null;};
/* locations */
E.locName=id=>{const l=W.S.locations.find(x=>x.id===id);if(!l)return 'Unassigned';const p=l.parent&&W.S.locations.find(x=>x.id===l.parent);return p?p.name+' › '+l.name:l.name;};
E.locsFor=k=>W.S.locations.filter(l=>l.k===k);
/* inventory */
E.lots=k=>W.S.inv.filter(i=>!k||i.k===k);
E.expiry=lot=>{if(lot.exp)return E.parse(lot.exp);if(lot.bestBy)return E.parse(lot.bestBy);const f=E.food(lot.food);
 let base=E.addDays(new Date(lot.added||Date.now()),f.life||7);if(lot.opened){const o=E.addDays(E.parse(lot.opened),Math.min(f.life||7,['dairy','meat','poultry','seafood'].includes(f.cat)?5:30));if(o<base)base=o;}
 base.setHours(0,0,0,0);return base;};
E.daysLeft=lot=>Math.round((E.expiry(lot)-E.today())/DAY);
E.isUseSoon=lot=>E.daysLeft(lot)<=3;
E.isExpired=lot=>E.daysLeft(lot)<0;
E.lowAt=lot=>lot.low!=null&&lot.low!==''?+lot.low:(+lot.init||+lot.qty)*0.25;
E.isLow=lot=>+lot.qty>0&&+lot.qty<=E.lowAt(lot)&&!E.isExpired(lot);
E.daysLabel=n=>n<0?(n===-1?'Expired yesterday':'Expired '+(-n)+' days ago'):n===0?'Use today':n===1?'1 day left':n+' days left';
E.stock=k=>{const m={};for(const l of E.lots(k)){if(E.isExpired(l))continue;const f=E.food(l.food);const dim=E.unitDim(l.unit);m[l.food]=m[l.food]||{};m[l.food][dim]=(m[l.food][dim]||0)+E.toBase(l.qty,l.unit);}return m;};
/* appliances present in a kitchen */
E.hasItem=(k,code)=>((W.S.kitems[k]||{})[code]||0)>0;
/* ---- member constraints (health.v_member_constraints) ---- */
E.ageOf=m=>{if(m.age!=null&&m.age!=='')return [+m.age,+m.age+0.0001];const b=R.AGE_BANDS.find(x=>x[0]===m.band);return b?[b[2],b[3]]:null;};
E.ageLabel=m=>m.age!=null&&m.age!==''?String(m.age):((R.AGE_BANDS.find(x=>x[0]===m.band)||[])[1]||'');
E.questionsFor=m=>R.QUESTIONS.filter(q=>{if(q.consent&&W.S.consent.health!==true)return false;if(q.min==null)return true;const a=E.ageOf(m);if(!a)return false;return a[0]<q.max&&a[1]>q.min;});
E.progress=m=>{const qs=E.questionsFor(m);const a=m.answers||{};const n=qs.filter(q=>Array.isArray(a[q.c])).length;return {n,total:qs.length,done:n===qs.length};};
E.constraints=m=>{const a=m.answers||{},on=c=>(a[c]||[]).filter(x=>x!=='none');
 return {allergy:on('allergies'),intol:on('intolerances'),diet:on('diet'),health:W.S.consent.health===true?on('health_food'):[],like:on('likes'),dislike:on('dislikes'),avoid:on('avoid_foods').concat(on('not_yet_introduced')),prior:on('prioritize_foods')};};
E.membersIn=k=>W.S.members.filter(m=>m.k===k);
/* ---- matching engine ---- */
E.match=(k,memberIds)=>{
 const kit=E.kitchen(k);const stock=E.stock(kit&&kit.id);const mem=W.S.members.filter(m=>memberIds?memberIds.includes(m.id):true).map(m=>({m,c:E.constraints(m)}));
 const out=[];
 for(const r of R.RECIPES){const ev=[];let sum=0,cnt=0;const missing=[];
  for(const ing of r.ing){const f=E.food(ing.f);const dim=E.unitDim(ing.u);const need=E.toBase(ing.q,ing.u);const have=((stock[ing.f]||{})[dim])||0;
   if(!ing.opt){cnt++;sum+=need>0?Math.min(1,have/need):(have>0?1:0);if(have<need)missing.push({f:ing.f,need,have,dim,ing});}
   const anc=E.catAnc(f.cat);
   for(const {m,c} of mem){const nm=m.name;
    for(const al of f.al){if(c.allergy.includes(al))ev.push(['allergy','block',nm,'contains '+(R.ALLERGENS[al]||R.INTOL[al]||al).toLowerCase()]);
     if(c.intol.includes(al))ev.push(['intolerance','warn',nm,'contains '+(R.INTOL[al]||al).toLowerCase()]);}
    for(const d of c.diet){const x=R.DIET_EX[d]||{};if((x.c||[]).some(cc=>anc.includes(cc))||(x.f||[]).includes(f.id)||(x.a||[]).some(aa=>f.al.includes(aa)))ev.push(['diet','block',nm,R.DIETS[d]+': '+f.name.toLowerCase()]);}
    for(const p of c.avoid)if(anc.includes(p))ev.push(['preference','block',nm,'avoids '+R.CATS[p].n.toLowerCase()]);
    for(const p of c.dislike)if(anc.includes(p))ev.push(['preference','warn',nm,'dislikes '+R.CATS[p].n.toLowerCase()]);
    for(const p of c.like)if(anc.includes(p))ev.push(['preference','good',nm,'likes '+R.CATS[p].n.toLowerCase()]);
    for(const p of c.prior)if(anc.includes(p))ev.push(['preference','good',nm,'more '+R.CATS[p].n.toLowerCase()]);}}
  for(const {m,c} of mem)for(const h of c.health){const rule=R.HEALTH[h];if(!rule)continue;const v=r.n[rule.k];if(v==null)continue;
   if((rule.cmp==='max'&&v>rule.t)||(rule.cmp==='min'&&v<rule.t))ev.push(['health','warn',m.name,rule.n.toLowerCase()+': '+v+' '+rule.u+' '+R.NUTR[rule.k].toLowerCase()]);}
  for(const a of r.app)if(!kit||!E.hasItem(kit.id,a))ev.push(['appliance','block',null,'needs '+a.replace(/_/g,' ')]);
  const seen=new Set(),reasons=[];for(const e of ev){const key=e.join('|');if(!seen.has(key)){seen.add(key);reasons.push({type:e[0],sev:e[1],member:e[2],detail:e[3]});}}
  const blocked=reasons.some(x=>x.sev==='block'),warns=reasons.filter(x=>x.sev==='warn').length,goods=reasons.filter(x=>x.sev==='good').length;
  const avail=cnt?Math.round(100*sum/cnt):100;
  const fit=blocked?0:Math.max(0,Math.min(100,Math.round(0.7*avail+30-8*warns+4*goods)));
  out.push({r,fit,avail,blocked,reasons,missing});}
 return out.sort((a,b)=>(a.blocked-b.blocked)||(b.fit-a.fit)||a.r.title.localeCompare(b.r.title));};
/* ---- inventory mutations with ledger (hh.inventory_transactions) ---- */
E.tx=(lot,kind,deltaBase,note)=>{W.S.tx.unshift({id:W.uid(),lot:lot.id,food:lot.food,name:E.foodName(lot),k:lot.k,kind,d:deltaBase,dim:E.unitDim(lot.unit),at:Date.now(),note:note||''});if(W.S.tx.length>500)W.S.tx.length=500;};
/* consume base qty of a food from a kitchen, earliest expiry first. Returns consumed base. */
E.consume=(k,food,base,dim,kind)=>{let left=base;const lots=E.lots(k).filter(l=>l.food===food&&E.unitDim(l.unit)===dim).sort((a,b)=>E.expiry(a)-E.expiry(b));
 for(const l of lots){if(left<=0)break;const have=E.toBase(l.qty,l.unit);const take=Math.min(have,left);l.qty=E.fromBase(have-take,l.unit);left-=take;E.tx(l,kind||'use',-take);
  if(l.qty<=1e-6){W.S.inv=W.S.inv.filter(x=>x!==l);}}
 return base-left;};
E.alerts=k=>{const al=[];const lots=E.lots(k);const mem=E.membersIn(k);
 for(const l of lots){const f=E.food(l.food);for(const m of mem){const c=E.constraints(m);const hit=f.al.filter(a=>c.allergy.includes(a));if(hit.length)al.push({kind:'allergy',lot:l,member:m,text:E.foodName(l)+' contains '+hit.map(a=>(R.ALLERGENS[a]||a).toLowerCase()).join(', ')+'. '+m.name+' is allergic.'});}}
 return al;};
return E;});
