/* WAMWins core: state, persistence + cloud sync, router, UI kit, gestures. Feature modules load on demand. */
(function(){
'use strict';
const W=window.W=Object.assign(window.W||{},{defs:{},mods:{},screens:{},stack:[],f:{},acts:{}});
W.DEPS={engine:['ref'],setup:['engine'],home:['engine'],meals:['engine','inventory'],inventory:['engine'],kitchen:['engine'],household:['engine'],demo:['engine'],cloud:['engine']};
const LS='wamwins.v1';
W.e=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
W.uid=()=>(crypto.randomUUID?crypto.randomUUID():Date.now().toString(36)+Math.random().toString(36).slice(2,10));
W.def=(n,f)=>{W.defs[n]=f;};
W.use=n=>{if(!(n in W.mods)){const f=W.defs[n];if(!f)throw new Error('Module not loaded: '+n);W.mods[n]=f(W)||true;}return W.mods[n];};
/* chunk loader: in the PWA build each module is its own file (W.CHUNKS); in the single-file build all are inline */
const pending={};
W.load=function(n){const deps=(W.DEPS&&W.DEPS[n])||[];if(W.defs[n]&&deps.every(d=>W.defs[d])){deps.forEach(d=>W.load(d));return Promise.resolve(W.use(n));}if(!W.CHUNKS||!W.CHUNKS[n])return Promise.reject(new Error('Unknown module '+n));

 return pending[n]||(pending[n]=Promise.all(deps.map(W.load)).then(()=>W.defs[n]?W.use(n):new Promise((ok,no)=>{const s=document.createElement('script');s.src=W.CHUNKS[n];s.onload=()=>ok(W.use(n));s.onerror=no;document.head.appendChild(s);})));};
/* ---------- state ---------- */
W.blank=()=>({v:1,at:0,account:null,signedIn:false,consent:{privacy:null,health:null,log:[]},setup:{},about:{name:'',role:'',goals:[]},household:null,kitchens:[],active:null,members:[],locations:[],kitems:{},inv:[],tx:[],shop:[],meals:[],foods:[],ui:{}});
function loadLocal(){try{const s=localStorage.getItem(LS);if(s)return Object.assign(W.blank(),JSON.parse(s));}catch(e){}return null;}
W.S=loadLocal()||W.blank();
let cloudT=null;
W.saveLocal=function(){W.S.at=Date.now();try{localStorage.setItem(LS,JSON.stringify(W.S));}catch(e){}};
W.save=function(){W.saveLocal();clearTimeout(cloudT);cloudT=setTimeout(cloudPush,1800);W.onSaved&&W.onSaved();};
W.CLOUD=()=>!!(W.CONFIG&&W.CONFIG.supabaseUrl&&W.CONFIG.supabaseAnonKey);
W.commit=function(fn){fn(W.S);W.save();W.render();};
W.reset=function(){W.S=W.blank();try{localStorage.removeItem(LS);}catch(e){}W.save();};
/* ---------- cloud sync (claude.ai artifact runtime: private per-person subtree) ---------- */
const SLICES={profile:['account','about','consent','setup','ui'],home:['household','kitchens','active','members','foods'],kitchen:['locations','kitems'],stock:['inv','tx'],plan:['shop','meals']};
let cloud=null;
async function cloudInit(){try{if(!window.claude||!window.claude.use)return;const [db,user]=await Promise.all([window.claude.use('db'),window.claude.use('user')]);if(!db||!user)return;const id=await user.id();if(!id)return;
 cloud={db,base:'data/users/'+id+'/wam/'};const snaps=await Promise.all(Object.keys(SLICES).map(k=>db.doc(cloud.base+k).get()));
 const remote={};let at=0;snaps.forEach((s,i)=>{if(s.exists){const d=s.data();at=Math.max(at,d.at||0);try{Object.assign(remote,JSON.parse(d.json));}catch(e){}}});
 if(at>(W.S.at||0)&&Object.keys(remote).length){const pw=W.S.account&&W.S.account.pw;W.S=Object.assign(W.blank(),remote);if(W.S.account){if(pw)W.S.account.pw=pw;W.S.signedIn=true;}
  try{localStorage.setItem(LS,JSON.stringify(W.S));}catch(e){}W.boot(true);W.toast('Synced your household from your account');}
 else if(W.S.at)cloudPush();}catch(e){cloud=null;}}
async function cloudPush(){if(!cloud||!W.S.account)return;try{for(const k in SLICES){const o={};for(const f of SLICES[k])o[f]=W.S[f];if(k==='profile'&&o.account){o.account=Object.assign({},o.account);delete o.account.pw;}
 const json=JSON.stringify(o);const key=k+':'+json.length+':'+json.slice(0,40)+json.slice(-80);if(cloud['h_'+k]===key)continue;await cloud.db.doc(cloud.base+k).set({json,at:W.S.at});cloud['h_'+k]=key;}}catch(e){}}
W.cloudOn=()=>!!cloud;
/* ---------- icons ---------- */
const P={home:'<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',meals:'<path d="M7 3v8m-3-8v5a3 3 0 0 0 6 0V3M7 11v10M17 3c-2 2-3 4-3 7h3v11"/>',inventory:'<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="m3 8 9 5 9-5M12 13v8"/>',kitchen:'<rect x="5" y="2.5" width="14" height="19" rx="2"/><path d="M5 10h14M9 6v1.5M9 13.5V16"/>',household:'<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.6a3.5 3.5 0 0 1 0 6.8M21.5 20a6.5 6.5 0 0 0-4-6"/>',back:'<path d="m15 5-7 7 7 7"/>',plus:'<path d="M12 5v14M5 12h14"/>',minus:'<path d="M5 12h14"/>',check:'<path d="m5 12.5 4.5 4.5L19 7.5"/>',warn:'<path d="M12 3 2 20h20zM12 10v4M12 17v.5"/>',lock:'<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',shield:'<path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"/><path d="m8.5 12 2.5 2.5 4.5-5"/>',chev:'<path d="m9 5 7 7-7 7"/>',search:'<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',trash:'<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',edit:'<path d="M4 20h4L19 9l-4-4L4 16z"/>',cart:'<path d="M3 4h2l2.4 11h11L21 7H6.2"/><circle cx="9" cy="19.5" r="1.5"/><circle cx="17" cy="19.5" r="1.5"/>',clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',x:'<path d="M6 6l12 12M18 6 6 18"/>',flame:'<path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-3 2-4 2-7 2 1 3 3 3 5 1-2 0-6 0-8z"/>',user:'<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',cloud:'<path d="M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9.5 4.3 4.3 0 0 0 7 18z"/>',download:'<path d="M12 4v11m-5-5 5 5 5-5M5 20h14"/>'};
W.i=(n,s)=>'<svg class="ic'+(s?' '+s:'')+'" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+(P[n]||'')+'</svg>';
/* ---------- UI kit ---------- */
W.logo=s=>'<img class="logo" style="width:'+(s||44)+'px;height:'+(s||44)+'px" src="'+W.ICON+'" alt="WAMWins">';
W.top=(title,o)=>{o=o||{};return '<header class="top">'+(o.back!==false&&W.stack.length>1?'<button class="bk" data-act="back" aria-label="Back">'+W.i('back')+'<span>Back</span></button>':'<span class="bk ph"></span>')+'<div class="tt">'+W.e(title||'')+'</div>'+(o.right||W.logo(40))+'</header>'+(o.pct!=null?'<div class="bar" role="progressbar" aria-valuenow="'+o.pct+'" aria-valuemin="0" aria-valuemax="100"><i style="width:'+o.pct+'%"></i></div>':'');};
W.chip=(label,on,attrs,cls)=>'<button type="button" class="chip'+(on?' on':'')+(cls?' '+cls:'')+'" aria-pressed="'+!!on+'" '+(attrs||'')+'>'+(on?'<span class="ck">✓</span>':'')+W.e(label)+'</button>';
W.step=(val,act,attrs,min)=>'<div class="stp"><button type="button" class="sb" data-act="'+act+'" data-d="-1" '+(attrs||'')+' aria-label="Decrease"'+((+val||0)<=(min||0)?' disabled':'')+'>'+W.i('minus')+'</button><b>'+W.e(val)+'</b><button type="button" class="sb" data-act="'+act+'" data-d="1" '+(attrs||'')+' aria-label="Increase">'+W.i('plus')+'</button></div>';
W.field=(label,key,o)=>{o=o||{};const v=W.f[key]!=null?W.f[key]:(o.value!=null?o.value:'');const id='f_'+key;
 const ctl=o.options?'<select id="'+id+'" data-f="'+key+'"'+(o.req?' required':'')+'>'+(o.ph?'<option value="">'+W.e(o.ph)+'</option>':'')+o.options.map(x=>'<option value="'+W.e(x[0])+'"'+(String(x[0])===String(v)?' selected':'')+'>'+W.e(x[1])+'</option>').join('')+'</select>'
 :'<input id="'+id+'" data-f="'+key+'" type="'+(o.type||'text')+'" value="'+W.e(v)+'"'+(o.ph?' placeholder="'+W.e(o.ph)+'"':'')+(o.mode?' inputmode="'+o.mode+'"':'')+(o.ac?' autocomplete="'+o.ac+'"':'')+(o.min!=null?' min="'+o.min+'"':'')+(o.step?' step="'+o.step+'"':'')+(o.req?' required':'')+(o.list?' list="'+o.list+'"':'')+'>';
 return '<label class="fld'+(o.cls?' '+o.cls:'')+'" for="'+id+'"><span>'+W.e(label)+(o.opt?' <em>optional</em>':'')+'</span>'+ctl+(o.err?'<small class="er">'+W.e(o.err)+'</small>':'')+'</label>';};
W.kSwitch=(act)=>{const S=W.S;if(S.kitchens.length<2)return '';return '<div class="ksw" role="tablist">'+S.kitchens.map(k=>W.chip(k.name+' · '+k.country,k.id===S.active,'role="tab" data-act="'+(act||'kitchen')+'" data-id="'+k.id+'"','kc')).join('')+'</div>';};
W.av=(name,cls)=>'<span class="av'+(cls?' '+cls:'')+'" aria-hidden="true">'+W.e((name||'?').trim().charAt(0).toUpperCase())+'</span>';
W.empty=(title,text,btn)=>'<div class="empty"><b>'+W.e(title)+'</b><p>'+W.e(text)+'</p>'+(btn||'')+'</div>';
W.acts.kitchen=el=>{W.S.active=el.dataset.id;W.save();W.render();};
/* ---------- router ---------- */
W.MAP={};/* screen → module, filled by registry below */
W.TABS=['home','meals','inventory','kitchen','household'];
const app=()=>document.getElementById('app');
W.go=async function(name,p,o){o=o||{};const mod=W.MAP[name];document.body.classList.add('busy');
 try{await W.load(mod);}catch(e){document.body.classList.remove('busy');W.toast('Could not load this screen. Check your connection.');return;}
 document.body.classList.remove('busy');W.f=o.keepF?W.f:{};
 if(o.root)W.stack=[{name,p:p||{}}];else if(o.replace&&W.stack.length)W.stack[W.stack.length-1]={name,p:p||{}};else W.stack.push({name,p:p||{}});
 W.render(true);};
W.back=function(){if(W.stack.length>1){W.stack.pop();W.f={};W.render(true);}};
W.acts.back=()=>W.back();
W.acts.tab=el=>W.go(el.dataset.t,{},{root:true});
let lastKey='';
W.render=function(fresh){const top=W.stack[W.stack.length-1];if(!top)return;const sc=W.screens[top.name];if(!sc)return;
 const view=document.getElementById('view');const sEl=view.querySelector('.scroll');const key=top.name+W.stack.length;const st=(!fresh&&key===lastKey&&sEl)?sEl.scrollTop:0;
 const ae=document.activeElement;const focusKey=ae&&ae.dataset&&ae.dataset.f;const selS=ae&&ae.selectionStart;
 view.innerHTML=sc.render(top.p||{});lastKey=key;
 const ns=view.querySelector('.scroll');if(ns)ns.scrollTop=st;
 if(focusKey){const el=view.querySelector('[data-f="'+focusKey+'"]');if(el){el.focus();try{if(selS!=null)el.setSelectionRange(selS,selS);}catch(e){}}}
 const tab=sc.tab;const nav=document.getElementById('nav');nav.hidden=!tab;if(tab)nav.querySelectorAll('button').forEach(b=>{const on=b.dataset.t===tab;b.classList.toggle('on',on);on?b.setAttribute('aria-current','page'):b.removeAttribute('aria-current');});
 if(fresh&&!focusKey){view.classList.remove('in');void view.offsetWidth;view.classList.add('in');}
 sc.mount&&sc.mount(view,top.p||{});};
/* ---------- event delegation ---------- */
function findAct(name){const top=W.stack[W.stack.length-1];const sc=top&&W.screens[top.name];const sh=W._sheet;return (sh&&sh.acts&&sh.acts[name])||(sc&&sc.acts&&sc.acts[name])||W.acts[name];}
document.addEventListener('click',e=>{const el=e.target.closest('[data-act]');if(!el||el.disabled)return;const fn=findAct(el.dataset.act);if(fn){e.preventDefault();fn(el,e);}});
document.addEventListener('input',e=>{const el=e.target.closest('[data-f]');if(!el)return;W.f[el.dataset.f]=el.type==='checkbox'?el.checked:el.value;const top=W.stack[W.stack.length-1];const sc=top&&W.screens[top.name];const fn=(W._sheet&&W._sheet.onInput)||(sc&&sc.onInput);fn&&fn(el.dataset.f,el);});
document.addEventListener('change',e=>{const el=e.target.closest('select[data-f]');if(!el)return;const top=W.stack[W.stack.length-1];const sc=top&&W.screens[top.name];const fn=(W._sheet&&W._sheet.onChange)||(sc&&sc.onChange);fn&&fn(el.dataset.f,el);});
document.addEventListener('submit',e=>e.preventDefault());
/* ---------- toast / sheet / confirm ---------- */
let toastT;
W.toast=function(msg,o){o=o||{};const t=document.getElementById('toast');t.innerHTML='<span>'+W.e(msg)+'</span>'+(o.action?'<button type="button" id="tact">'+W.e(o.action)+'</button>':'');t.className='show';
 if(o.action)document.getElementById('tact').onclick=()=>{t.className='';o.fn&&o.fn();};clearTimeout(toastT);toastT=setTimeout(()=>{t.className='';},o.ms||(o.action?5000:2600));};
W.sheet=function(html,o){o=o||{};W.closeSheet(true);const ov=document.createElement('div');ov.className='ov';ov.innerHTML='<div class="sheet" role="dialog" aria-modal="true" aria-label="'+W.e(o.label||'Details')+'"><div class="grab" aria-hidden="true"><i></i></div><div class="shb">'+html+'</div></div>';
 document.body.appendChild(ov);W._sheet=Object.assign({el:ov},o);requestAnimationFrame(()=>ov.classList.add('open'));
 ov.addEventListener('click',e=>{if(e.target===ov)W.closeSheet();});dragSheet(ov.querySelector('.sheet'));
 const f=ov.querySelector('input,select,button:not(.grab)');if(f&&o.focus!==false)setTimeout(()=>f.focus({preventScroll:true}),180);return ov;};
W.resheet=function(html){if(W._sheet)W._sheet.el.querySelector('.shb').innerHTML=html;};
W.closeSheet=function(now){const s=W._sheet;if(!s)return;W._sheet=null;const el=s.el;if(now){el.remove();}else{el.classList.remove('open');setTimeout(()=>el.remove(),220);}s.onClose&&s.onClose();};
W.acts.closeSheet=()=>W.closeSheet();
W.confirm=o=>new Promise(res=>{W.sheet('<h2>'+W.e(o.title)+'</h2>'+(o.body?'<p class="mt8">'+W.e(o.body)+'</p>':'')+'<div class="col mt16"><button class="btn'+(o.danger?' dg':'')+'" data-act="cOk">'+W.e(o.ok||'Confirm')+'</button><button class="btn o" data-act="cNo">Cancel</button></div>',{label:o.title,acts:{cOk:()=>{W._sheet.onClose=null;W.closeSheet();res(true);},cNo:()=>{W.closeSheet();}},onClose:()=>res(false)});});
/* ---------- gestures ---------- */
function dragSheet(sh){let y0=null,dy=0;const g=sh.querySelector('.grab');
 g.addEventListener('pointerdown',e=>{y0=e.clientY;dy=0;g.setPointerCapture(e.pointerId);sh.style.transition='none';});
 g.addEventListener('pointermove',e=>{if(y0==null)return;dy=Math.max(0,e.clientY-y0);sh.style.transform='translateY('+dy+'px)';});
 const end=()=>{if(y0==null)return;y0=null;sh.style.transition='';sh.style.transform='';if(dy>90)W.closeSheet();};g.addEventListener('pointerup',end);g.addEventListener('pointercancel',end);}
/* swipe rows: .sw > .swf (foreground). Left reveals actions; right triggers data-right act */
let sw=null;
document.addEventListener('pointerdown',e=>{const f=e.target.closest('.swf');document.querySelectorAll('.sw.open').forEach(x=>{if(!f||x!==f.parentNode){x.classList.remove('open');x.querySelector('.swf').style.transform='';}});
 if(!f||e.pointerType==='mouse'&&e.button!==0)return;sw={f,x0:e.clientX,y0:e.clientY,dx:0,lock:null,open:f.parentNode.classList.contains('open'),id:e.pointerId};});
document.addEventListener('pointermove',e=>{if(!sw||e.pointerId!==sw.id)return;const dx=e.clientX-sw.x0,dy=e.clientY-sw.y0;
 if(sw.lock==null&&(Math.abs(dx)>8||Math.abs(dy)>8))sw.lock=Math.abs(dx)>Math.abs(dy)?'x':'y';if(sw.lock!=='x')return;
 const right=!!sw.f.parentNode.dataset.right;const base=sw.open?-148:0;sw.dx=Math.max(-170,Math.min(right?110:0,base+dx));sw.f.style.transition='none';sw.f.style.transform='translateX('+sw.dx+'px)';sw.f.classList.add('drag');});
document.addEventListener('pointerup',e=>{if(!sw||e.pointerId!==sw.id)return;const s=sw;sw=null;s.f.style.transition='';
 if(s.lock!=='x'){return;}const row=s.f.parentNode;s.f.classList.remove('drag');
 const block=ev=>{ev.stopPropagation();ev.preventDefault();};document.addEventListener('click',block,{capture:true,once:true});setTimeout(()=>document.removeEventListener('click',block,{capture:true}),50);
 if(s.dx<-70){row.classList.add('open');s.f.style.transform='translateX(-148px)';}
 else if(s.dx>80&&row.dataset.right){s.f.style.transform='';row.classList.remove('open');const fn=findAct(row.dataset.right);fn&&fn(row);}
 else{row.classList.remove('open');s.f.style.transform='';}});
document.addEventListener('pointercancel',()=>{if(sw){sw.f.style.transform='';sw=null;}});
/* edge swipe → back */
let edge=null;
document.addEventListener('touchstart',e=>{const t=e.touches[0];edge=(t.clientX<22&&W.stack.length>1&&!W._sheet)?{x:t.clientX,y:t.clientY}:null;},{passive:true});
document.addEventListener('touchend',e=>{if(!edge)return;const t=e.changedTouches[0];if(t.clientX-edge.x>80&&Math.abs(t.clientY-edge.y)<60)W.back();edge=null;},{passive:true});
document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(W._sheet)W.closeSheet();}});
/* ---------- boot ---------- */
W.boot=function(again){const S=W.S;
 if(!S.account||!S.signedIn){W.go('welcome',{},{root:true});}
 else if(!S.consent.privacy){W.go('privacy',{},{root:true});}
 else if(!S.household){W.go('setup',{},{root:true});}
 else W.go(again&&W.stack.length&&W.TABS.includes(W.stack[0].name)?W.stack[0].name:'home',{},{root:true});};
window.addEventListener('DOMContentLoaded',()=>{
 const nav=document.getElementById('nav');nav.innerHTML=[['home','Home'],['meals','Meals'],['inventory','Inventory'],['kitchen','Kitchen'],['household','Household']].map(x=>'<button type="button" data-act="tab" data-t="'+x[0]+'">'+W.i(x[0])+'<span>'+x[1]+'</span></button>').join('');
 W.boot();if(W.CLOUD()){W.load('cloud').then(c=>c.start()).then(t=>{W.boot(true);if(t==='recovery')W.load('auth').then(()=>W.recoverySheet&&W.recoverySheet());}).catch(()=>{});}else setTimeout(cloudInit,50);
 if(W.SW&&'serviceWorker' in navigator&&location.protocol==='https:')navigator.serviceWorker.register(W.SW).catch(()=>{});});
})();
W.MAP={welcome:'auth',signup:'auth',signin:'auth',verify:'auth',privacy:'auth',
 setup:'setup',about:'setup',hh:'setup',family:'setup',member:'setup',needs:'setup',storage:'setup',items:'setup',finish:'setup',
 home:'home',meals:'meals',recipe:'meals',inventory:'inventory',addfood:'inventory',kitchen:'kitchen',household:'household'};
W.applyTheme=()=>{const t=(W.S.ui||{}).theme;const r=document.documentElement;if(t==='light'||t==='dark')r.dataset.theme=t;else delete r.dataset.theme;};
W.applyTheme();
