const C='pdffacil-v2';
const F=['./','index.html','manifest.webmanifest','icon-192.png','icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(F)).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x.startsWith('pdffacil-v')&&x!==C).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
if(e.request.method==='POST'&&new URL(e.request.url).pathname.endsWith('/share')){
e.respondWith((async()=>{try{const fd=await e.request.formData(),f=fd.get('pdf');
if(f){const c=await caches.open('pdffacil-share');await c.put('shared-pdf',new Response(f,{headers:{'X-Name':encodeURIComponent(f.name||'arquivo.pdf')}}))}}catch(x){}
return Response.redirect(new URL('./?shared=1',self.registration.scope).href,303)})());return}
if(e.request.method!=='GET')return;
e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(C).then(x=>x.put(e.request,c));return r}).catch(()=>caches.match(e.request,{ignoreSearch:true})))});
