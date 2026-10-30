import subprocess,base64,os,json,shutil,hashlib,zipfile
APP='/home/claude/app';B='/home/claude/build';ESB='/home/claude/.npm-global/lib/node_modules/tsx/node_modules/@esbuild/linux-x64/bin/esbuild'
def mini(path,loader='js'):
    r=subprocess.run([ESB,'--minify','--loader='+loader,'--target=es2020' if loader=='js' else '--target=chrome87,safari14'],input=open(path,'rb').read(),capture_output=True)
    if r.returncode: raise SystemExit(path+'\n'+r.stderr.decode())
    return r.stdout.decode()
b64=lambda f,m:'data:'+m+';base64,'+base64.b64encode(open(f,'rb').read()).decode()
MODS=['ref','engine','auth','setup','home','meals','inventory','kitchen','household','demo']
PWA_MODS=MODS+['cloud']
FILES={'ref':'data.js','engine':'engine.js','auth':'m_auth.js','setup':'m_setup.js','home':'m_home.js','meals':'m_meals.js','inventory':'m_inventory.js','kitchen':'m_kitchen.js','household':'m_household.js','demo':'m_demo.js','cloud':'m_cloud.js'}
css=mini(APP+'/style.css','css');core=mini(APP+'/core.js')
mods={m:mini(APP+'/'+FILES[m]) for m in PWA_MODS}
FONTS='<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap" rel="stylesheet">'
HEAD='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="theme-color" content="#0B49D1"><meta name="description" content="WAMWins Basic: organize food, understand your family’s needs and decide what to cook with what you already have."><title>WAMWins Basic</title>'
BODY='<div id="app"><main id="view"></main><nav id="nav" hidden aria-label="Main"></nav></div><div id="toast" role="status" aria-live="polite"></div>'
# ---- single file (artifact) ----
assets='window.W={LOGO:"%s",ICON:"%s"};'%(b64(B+'/logo_full_240.webp','image/webp'),b64(B+'/icon_96.webp','image/webp'))
single=HEAD+'<link rel="icon" href="'+b64(B+'/icon_96.webp','image/webp')+'">'+FONTS+'<style>'+css+'</style></head><body>'+BODY+'<script>'+assets+'</script><script>'+core+'</script>'+''.join('<script>'+mods[m]+'</script>' for m in MODS)+'</body></html>'
os.makedirs('/mnt/user-data/outputs',exist_ok=True)
open('/mnt/user-data/outputs/wamwins.html','w').write(single)
print('single',len(single))
# ---- PWA bundle (true code splitting) ----
P='/home/claude/pwa';shutil.rmtree(P,ignore_errors=True);os.makedirs(P+'/js');os.makedirs(P+'/icons')
h=lambda s:hashlib.sha1(s.encode()).hexdigest()[:8]
chunks={}
for m in PWA_MODS:
    fn='js/%s.%s.js'%(m,h(mods[m]));open(P+'/'+fn,'w').write(mods[m]);chunks[m]=fn
cfn='js/core.%s.js'%h(core);open(P+'/'+cfn,'w').write(core)
for f in ['icon_96.webp','logo_full_240.webp','icon_192.png','icon_512.png','icon_maskable_512.png']:shutil.copy(B+'/'+f,P+'/icons/'+f)
cfg='window.W=Object.assign(window.W||{},{LOGO:"icons/logo_full_240.webp",ICON:"icons/icon_96.webp",SW:"sw.js",CHUNKS:%s});'%json.dumps(chunks)
idx=HEAD+'<link rel="manifest" href="manifest.webmanifest"><link rel="icon" href="icons/icon_96.webp"><link rel="apple-touch-icon" href="icons/icon_192.png"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="default"><link rel="preload" href="icons/logo_full_240.webp" as="image">'+FONTS+'<style>'+css+'</style></head><body>'+BODY+'<script src="config.js"></script><script>'+cfg+'</script><script src="'+cfn+'" defer></script><script src="'+chunks['auth']+'" defer></script></body></html>'
open(P+'/index.html','w').write(idx)
man={"name":"WAMWins Basic","short_name":"WAMWins","description":"Make your kitchen work smarter for your family.","start_url":"./","scope":"./","display":"standalone","orientation":"portrait","background_color":"#FFFFFF","theme_color":"#0B49D1","categories":["food","lifestyle","productivity"],
 "icons":[{"src":"icons/icon_192.png","sizes":"192x192","type":"image/png"},{"src":"icons/icon_512.png","sizes":"512x512","type":"image/png"},{"src":"icons/icon_maskable_512.png","sizes":"512x512","type":"image/png","purpose":"maskable"}]}
open(P+'/manifest.webmanifest','w').write(json.dumps(man,indent=1))
shell=['./','index.html','config.js','manifest.webmanifest',cfn,chunks['auth'],'icons/icon_96.webp','icons/logo_full_240.webp']
lazy=[chunks[m] for m in PWA_MODS if m!='auth']
ver=h(idx+''.join(mods.values()))
CONFIG=os.environ.get('WAM_CONFIG') or open(APP+'/config.js').read()
open(P+'/config.js','w').write(CONFIG)
sw='''const V='wam-%s',SHELL=%s,LAZY=%s;
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(SHELL).then(()=>c.addAll(LAZY).catch(()=>{}))));self.skipWaiting();});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',e=>{const r=e.request;if(r.method!=='GET')return;const u=new URL(r.url);
 if(u.origin===location.origin){if(u.pathname.endsWith('/config.js')){e.respondWith(fetch(r).then(x=>{const c=x.clone();caches.open(V).then(k=>k.put(r,c));return x;}).catch(()=>caches.match(r)));return;}if(r.mode==='navigate'){e.respondWith(fetch(r).then(x=>{const c=x.clone();caches.open(V).then(k=>k.put('index.html',c));return x;}).catch(()=>caches.match('index.html')));return;}
  e.respondWith(caches.match(r).then(x=>x||fetch(r).then(y=>{if(y.ok){const c=y.clone();caches.open(V).then(k=>k.put(r,c));}return y;})));return;}
 if(/fonts\\.(googleapis|gstatic)\\.com$/.test(u.hostname))e.respondWith(caches.open(V+'-f').then(c=>c.match(r).then(x=>{const n=fetch(r).then(y=>{c.put(r,y.clone());return y;}).catch(()=>x);return x||n;})));});
'''%(ver,json.dumps(shell),json.dumps(lazy))
open(P+'/sw.js','w').write(sw)
shutil.copy(APP+'/../README_PWA.md',P+'/README.md') if os.path.exists(APP+'/../README_PWA.md') else None
src=P+'/src';os.makedirs(src)
for f in list(FILES.values())+['core.js','style.css','config.js']:shutil.copy(APP+'/'+f,src+'/'+f)
D=P+'/database';os.makedirs(D)
for f in sorted(os.listdir('/home/claude/src/wamwins-db/wamwins-db')):shutil.copy('/home/claude/src/wamwins-db/wamwins-db/'+f,D+'/'+f)
for f in sorted(os.listdir('/home/claude/db')):shutil.copy('/home/claude/db/'+f,D+'/'+f)
if os.path.exists(APP+'/README.md'):shutil.copy(APP+'/README.md',P+'/README.md')
shutil.copy('/home/claude/build.py',src+'/build.py')
z='/mnt/user-data/outputs/wamwins-pwa.zip'
with zipfile.ZipFile(z,'w',zipfile.ZIP_DEFLATED) as zf:
    for root,_,fs in os.walk(P):
        for f in fs:fp=os.path.join(root,f);zf.write(fp,'wamwins-pwa/'+os.path.relpath(fp,P))
for root,_,fs in os.walk(P):
    for f in fs:
        if '/src' in root or '/database' in root: continue
        fp=os.path.join(root,f);print(os.path.relpath(fp,P),os.path.getsize(fp))
