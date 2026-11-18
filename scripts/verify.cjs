const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {chromium} = require('playwright');
const {default: AxeBuilder} = require('@axe-core/playwright');
const {createServer, prefix} = require('./serve.cjs');
const {origin, pages, notFound, htmlFiles} = require('./site.cjs');

// Tests launch their own local server; no production writes or downloads.
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'test-results');
const handoff = path.join(output, 'handoff');
const port = 18765;
const base = `http://127.0.0.1:${port}${prefix}/`;
const url = base;
const featurePages = pages.filter(p => p.id !== 'home');
const programmaticKeys = ['theme','nav.menu','copy.pending','copy.ok','copy.error','demo.stop','growth.play','growth.pause',
  ...[...featurePages, notFound].flatMap(p => [`meta.${p.id}.title`, `meta.${p.id}.desc`])];
const results = [];
const problems = [];
fs.mkdirSync(handoff, {recursive:true});
const server = createServer();

async function test(name, fn) {
  let timer;
  const limit=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timed out after 180s')),180000);});
  try {await Promise.race([fn(),limit]);results.push({name,status:'pass'});}
  catch(error) {problems.push({name,error:error.message});results.push({name,status:'fail'});console.log(`FAIL ${name}: ${error.message.split('\n')[0]}`);}
  finally {clearTimeout(timer);}
}
function read(file) {return fs.readFileSync(path.join(root, file), 'utf8');}
function swiftSource() {
  try {return execFileSync('git',['show','origin/main:Sources/PokeTokenBar/Core/CompanionModel.swift'],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','ignore']});}
  catch {return null;}
}
function appBalance(source) {
  const block=name=>{const start=source.indexOf(`enum ${name}`);assert.ok(start>=0,`enum ${name} not found in CompanionModel.swift`);return source.slice(start,source.indexOf('\n}\n',start)+1);};
  const constant=(text,name)=>{
    const match=text.match(new RegExp(`static let ${name}(?::[^=\\n]+)?\\s*=\\s*([\\d_ .*]+)\\n`));
    assert.ok(match,`static let ${name} not found in CompanionModel.swift`);
    return match[1].replace(/_/g,'').split('*').reduce((product,part)=>product*Number(part.trim()),1);
  };
  const click=block('ClickGrowth'), balance=block('PokemonBalance');
  const total=rarity=>{const match=balance.match(new RegExp(`case \\.${rarity}:\\s*return\\s*([\\d_]+)`));assert.ok(match,`graduationTotal(.${rarity}) not found`);return Number(match[1].replace(/_/g,''));};
  const range=balance.match(/static let difficultyRange[^=]*=\s*([\d.]+)\.\.\.([\d.]+)/);
  assert.ok(range,'difficultyRange not found in CompanionModel.swift');
  return {
    graduationTotal:Object.fromEntries(['common','uncommon','rare','legendary'].map(r=>[r,total(r)])),
    eggHatchThreshold:constant(balance,'eggHatchThreshold'),
    repeatGrowthMultiplier:constant(balance,'repeatGrowthMultiplier'),
    difficultyRange:[Number(range[1]),Number(range[2])],
    timeTokensPerActiveHour:constant(balance,'timeTokensPerActiveHour'),
    timeWalletTokensPerActiveHour:constant(balance,'timeWalletTokensPerActiveHour'),
    timeIdleLimitSeconds:constant(balance,'timeIdleLimit'),
    timeMaxStepSeconds:constant(balance,'timeMaxStep'),
    idleTokenHintAfterSeconds:constant(balance,'idleTokenHintAfter'),
    tokensPerClick:constant(click,'tokensPerClick'),
    clickMinIntervalSeconds:constant(click,'minInterval')
  };
}
async function layout(page) {
  const state=await page.evaluate(()=>({
    overflow:document.documentElement.scrollWidth > innerWidth,
    broken:[...document.images].filter(x=>x.complete&&!x.naturalWidth).map(x=>x.getAttribute('src')),
    missing:[...document.querySelectorAll('[data-i18n]')].filter(x=>!x.textContent.trim()).map(x=>x.dataset.i18n),
    duplicates:[...document.querySelectorAll('[id]')].map(x=>x.id).filter((id,i,ids)=>ids.indexOf(id)!==i)
  }));
  assert.equal(state.overflow,false,JSON.stringify(state));assert.deepEqual(state.broken,[]);assert.deepEqual(state.missing,[]);assert.deepEqual(state.duplicates,[]);
}
async function loadAll(page) {
  await page.evaluate(async()=>{for(let y=0;y<document.body.scrollHeight;y+=700){scrollTo(0,y);await new Promise(r=>setTimeout(r,15));}scrollTo(0,0);await document.fonts.ready;});
  await page.waitForFunction(()=>[...document.images].every(i=>i.complete));
}
async function capture(page,name,full=false,dir=output) {
  await loadAll(page);
  await page.screenshot({path:path.join(dir,name+'.png'),fullPage:full});
}
async function axe(page) {
  return (await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze()).violations;
}
function expectNoViolations(violations,name) {
  if(violations.length)fs.writeFileSync(path.join(output,`axe-${name}.json`),JSON.stringify(violations,null,2));
  assert.deepEqual(violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)})),[]);
}
async function dictionaries(browser) {
  const p=await browser.newPage();
  try {await p.goto(url);return await p.evaluate(()=>I18N);}finally{await p.close();}
}

(async()=>{
 let browser;
 try {
  await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
  await test('every page links tokens.css, styles.css, pages-i18n.js and app.js with ?v= equal to their content hash (npm run stamp)',async()=>{
   const {staleReferences}=require('./stamp.cjs');
   assert.deepEqual(htmlFiles.flatMap(file=>staleReferences(read(file)).map(ref=>`${file}: ${ref}`)),[]);
  });
  await test('every page has a title, a description and its own canonical URL; the sitemap lists every page',async()=>{
   const sitemap=read('sitemap.xml');
   const listed=[...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m=>m[1]);
   assert.deepEqual(listed.sort(),pages.map(p=>origin+p.path).sort());
   for(const p of [...pages,notFound]) {
    const html=read(p.file);
    assert.match(html,/<title>[^<]+<\/title>/,p.file);
    assert.match(html,/<meta name="description" content="[^"]+">/,p.file);
    assert.ok(html.includes(`<link rel="canonical" href="${origin+p.path}">`),`${p.file} canonical`);
    if(p!==notFound) {
     assert.ok(html.includes(`<meta property="og:url" content="${origin+p.path}">`)||p.id==='home',`${p.file} og:url`);
     assert.match(html,/<meta property="og:title" content="[^"]+">/,p.file);
    }
   }
  });
  for(let i=0;i<60;i++) {try {const response=await fetch(url);if(response.ok)break;}catch{} await new Promise(r=>setTimeout(r,100));}
  const executablePath=process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  browser=await chromium.launch({executablePath,headless:true});
  const I18N=await dictionaries(browser);

  await test('translation keys agree in every language; no key is missing or unused on any page; ko never says 도장',async()=>{
   for(const lang of ['ko','ja']) {
    assert.deepEqual(Object.keys(I18N.en).filter(k=>!(k in I18N[lang])),[],`missing in ${lang}`);
    assert.deepEqual(Object.keys(I18N[lang]).filter(k=>!(k in I18N.en)),[],`extra in ${lang}`);
   }
   const used=new Set(programmaticKeys);
   for(const file of htmlFiles)for(const m of read(file).matchAll(/data-i18n(?:-alt|-aria)?="([^"]+)"/g))used.add(m[1]);
   assert.deepEqual([...used].filter(k=>!(k in I18N.en)),[],'used but undefined');
   assert.deepEqual(Object.keys(I18N.en).filter(k=>!used.has(k)),[],'defined but unused');
   assert.deepEqual(Object.entries(I18N.ko).filter(([,v])=>v.includes('도장')).map(([k])=>k),[]);
  });

  await test('every nav, footer and page-list link to this site resolves; the current page carries aria-current',async()=>{
   const checked=new Set();
   for(const p of [...pages,notFound]) {
    const html=read(p.file);
    const pageUrl=new URL(p.path,base);
    const nav=html.match(/<nav class="nav-links"[^>]*>(.*?)<\/nav>/s)[1];
    const current=[...nav.matchAll(/<a [^>]*aria-current="page"[^>]*>/g)].map(m=>m[0].match(/href="([^"]+)"/)[1]);
    if(p.id==='home'||p===notFound)assert.deepEqual(current,[],p.file);
    else assert.deepEqual(current.map(h=>new URL(h,pageUrl).href),[pageUrl.href],p.file);
    for(const m of html.matchAll(/<a [^>]*href="([^"#]*)(#[^"]*)?"[^>]*data-internal/g)) {
     const target=new URL(m[1],pageUrl);
     if(checked.has(target.href+(m[2]||'')))continue;
     checked.add(target.href+(m[2]||''));
     const response=await fetch(target);
     assert.equal(response.status,200,`${p.file} → ${target.href}`);
     if(m[2]&&m[2]!=='#top') assert.ok((await response.text()).includes(`id="${m[2].slice(1)}"`),`${p.file} → ${m[0]}`);
    }
   }
  });

  await test('an unknown deep path answers 404 with the styled 404 page and working links',async()=>{
   const response=await fetch(new URL('no/such/page/',base));
   assert.equal(response.status,404);
   const p=await browser.newPage({viewport:{width:375,height:812}});
   const errors=[];p.on('pageerror',e=>errors.push(e.message));
   try {
    await p.goto(new URL('no/such/page/',base).href);
    await loadAll(p);
    assert.equal(await p.evaluate(()=>getComputedStyle(document.body).fontFamily.includes('Pretendard')||getComputedStyle(document.querySelector('.site-header')).position==='sticky'),true);
    await layout(p);
    assert.equal(await p.locator('.page-list a').count(),featurePages.length);
    await p.locator('.page-list a').first().click();
    await p.waitForURL(new URL('usage/',base).href);
    assert.deepEqual(errors,[]);
   }finally{await p.close();}
  });

  for(const p of [...pages,notFound]) for(const lang of ['en','ko','ja']) for(const width of [375,1440]) for(const theme of ['light','dark']) {
   await test(`page ${p.id} / ${lang} / ${width}px / ${theme}: layout, native images and axe WCAG 2.2 AA`,async()=>{
    const context=await browser.newContext({viewport:{width,height:900},reducedMotion:'reduce'});
    const page=await context.newPage();
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    try {
     await page.addInitScript(({lang,theme})=>{localStorage.setItem('ptb-lang',lang);localStorage.setItem('ptb-theme',theme);},{lang,theme});
     await page.goto(new URL(p.path,base).href);
     assert.equal(await page.locator('html').getAttribute('lang'),lang);
     assert.equal(await page.locator('html').getAttribute('data-theme'),theme);
     await loadAll(page);
     await layout(page);
     const expectedTitle=p.id==='home'?`PokeTokenBar — ${I18N[lang]['hero.h1a']} ${I18N[lang]['hero.h1b']}`:I18N[lang][`meta.${p.id}.title`];
     assert.equal(await page.title(),expectedTitle);
     const suffix=lang==='en'?'':'-'+lang;
     const native=await page.locator('[data-i18n-image]').evaluateAll(images=>images.map(i=>({src:i.getAttribute('src'),loaded:i.complete&&i.naturalWidth>0,caption:i.closest('figure')?.querySelector('figcaption')?.textContent||''})));
     assert.equal(native.length,(read(p.file).match(/data-i18n-image=/g)||[]).length);
     for(const i of native) {assert.ok(i.loaded,JSON.stringify(i));assert.ok(i.src.endsWith(suffix+'.png'),JSON.stringify(i));assert.ok(i.caption.trim(),JSON.stringify(i));}
     expectNoViolations(await axe(page),`${p.id}-${lang}-${width}-${theme}`);
     if(lang==='ko'&&theme==='light') await capture(page,`${p.id}-ko-${width}`,true,handoff);
     assert.deepEqual(errors,[]);
    }finally{await context.close();}
   });
  }

  for(const p of [...pages,notFound]) {
   await test(`page ${p.id}: menu opens, moves focus, closes on Escape and on resize at 375px`,async()=>{
    const page=await browser.newPage({viewport:{width:375,height:812},reducedMotion:'reduce'});
    try {
     await page.goto(new URL(p.path,base).href);
     assert.equal(await page.locator('#site-nav').isVisible(),false);
     await page.locator('#menuBtn').focus();await page.keyboard.press('Enter');
     assert.equal(await page.locator('#site-nav').isVisible(),true);
     assert.equal(await page.locator('#menuBtn').getAttribute('aria-expanded'),'true');
     assert.equal(await page.evaluate(()=>document.activeElement.closest('#site-nav')!==null),true);
     await page.keyboard.press('Tab');
     assert.equal(await page.evaluate(()=>document.activeElement.closest('#site-nav')!==null),true);
     await page.keyboard.press('Escape');
     assert.equal(await page.locator('#site-nav').isVisible(),false);
     assert.equal(await page.locator('#menuBtn').evaluate(x=>x===document.activeElement),true);
     await page.locator('#menuBtn').click();
     await page.setViewportSize({width:1440,height:900});
     await page.waitForFunction(()=>document.getElementById('menuBtn').getAttribute('aria-expanded')==='false',null,{timeout:5000});
     assert.equal(await page.locator('#site-nav').isVisible(),true);
     assert.equal(await page.locator('#menuBtn').isVisible(),false);
    }finally{await page.close();}
   });
   await test(`page ${p.id}: JavaScript disabled still shows navigation, text and images`,async()=>{
    const page=await browser.newPage({javaScriptEnabled:false,viewport:{width:375,height:812}});
    try {
     await page.goto(new URL(p.path,base).href);
     assert.equal(await page.locator('#site-nav').isVisible(),true);
     assert.equal(await page.locator('#menuBtn').isVisible(),false);
     for(const image of await page.locator('main img:visible').all()) {
      await image.scrollIntoViewIfNeeded();
      assert.ok(await image.evaluate(i=>i.complete&&i.naturalWidth>0||new Promise(r=>i.addEventListener('load',()=>r(true),{once:true}))),await image.getAttribute('src'));
     }
     await layout(page);
    }finally{await page.close();}
   });
  }

  await test('language: ?lang= wins, storage carries it to the next page, blocked storage carries it in links',async()=>{
   const context=await browser.newContext();
   try {
    const p=await context.newPage();
    await p.goto(new URL('battle/?lang=ja',base).href);
    assert.equal(await p.locator('html').getAttribute('lang'),'ja');
    await p.locator('#site-nav a[href="../items/"]').click();
    await p.waitForURL(/\/items\/$/);
    assert.equal(await p.locator('html').getAttribute('lang'),'ja');
    await p.locator('#language').selectOption('ko');
    await p.goto(base);
    assert.equal(await p.locator('html').getAttribute('lang'),'ko');
    await p.goto(new URL('growth/?lang=xx',base).href);
    assert.equal(await p.locator('html').getAttribute('lang'),'ko');
    await p.goto(new URL('growth/?lang=en',base).href);
    await p.locator('#language').selectOption('ja');
    assert.match(p.url(),/[?&]lang=ja/);
   }finally{await context.close();}
   const blocked=await browser.newPage();
   try {
    await blocked.addInitScript(()=>Object.defineProperty(window,'localStorage',{get(){throw Error('blocked');}}));
    await blocked.goto(new URL('collection/',base).href);
    await blocked.locator('#language').selectOption('ko');
    assert.match(await blocked.locator('#site-nav a[href*="battle/"]').getAttribute('href'),/battle\/\?lang=ko$/);
    assert.match(await blocked.locator('#site-nav a[href*="#install"]').getAttribute('href'),/\?lang=ko#install$/);
    await blocked.locator('#site-nav a[href*="battle/"]').click();
    await blocked.waitForURL(/battle\/\?lang=ko$/);
    assert.equal(await blocked.locator('html').getAttribute('lang'),'ko');
   }finally{await blocked.close();}
  });

  await test('home: growth calculator, install details and theme at every width in every language',async()=>{
   for(const lang of ['en','ko','ja']) for(const width of [320,375,414,768,1024,1100,1101,1440,1920]) {
    const p=await browser.newPage({viewport:{width,height:900},reducedMotion:'reduce'});
    const errors=[];p.on('pageerror',e=>errors.push(e.message));
    try {
     await p.addInitScript(lang=>localStorage.setItem('ptb-lang',lang),lang);
     await p.goto(url);await p.evaluate(()=>document.fonts.ready);
     assert.ok((await p.locator('html').getAttribute('class')).includes('js'));
     await layout(p);
     const header=await p.locator('.site-header').boundingBox();
     assert.ok(header.height<=(width>1100?90:130),`${lang} ${width}px header is ${header.height}px tall`);
     assert.equal(await p.locator('#gtab-growth').isVisible(),true);
     const lastWhen=()=>p.locator('#gTimeline .tl-when').last().innerText();
     assert.match(await lastWhen(),/(^|\D)4(\D|$)/);
     await p.locator('#gRarity').selectOption('legendary');
     assert.match(await lastWhen(),/(^|\D)28(\D|$)/);
     await p.locator('#gMode').selectOption('time');
     assert.equal(await p.locator('#gPaceField').isVisible(),false);
     assert.match(await lastWhen(),/^30\D+8(\D|$)/);
     assert.match(await p.locator('#gTimeline .tl-when').first().innerText(),/^2\D+1(\D|$)/);
     await layout(p);
     await p.locator('#gMode').selectOption('token');
     await p.locator('.install-more > summary').click();
     await layout(p);
     await p.locator('#themeBtn').click();
     assert.equal(await p.locator('html').getAttribute('data-theme'),'dark');
     await layout(p);
     assert.deepEqual(errors,[]);
    }finally{await p.close();}
   }
  });
  for(const lang of ['en','ko','ja']) for(const theme of ['light','dark']) await test(`home guide tabs axe WCAG 2.2 AA / ${lang} / ${theme}`,async()=>{
   const context=await browser.newContext({viewport:{width:1440,height:960},reducedMotion:'reduce'});
   const p=await context.newPage();
   try {
    await p.addInitScript(({lang,theme})=>{localStorage.setItem('ptb-lang',lang);localStorage.setItem('ptb-theme',theme);},{lang,theme});
    await p.goto(url);await p.evaluate(()=>{document.querySelectorAll('details').forEach(x=>x.open=true);});
    for(const tab of ['growth','daily','collect']) {
     await p.locator(`#tab-${tab}`).click();
     expectNoViolations(await axe(p),`home-${lang}-${theme}-${tab}`);
    }
   }finally{await context.close();}
  });
  await test('clipboard success, rejection, unsupported; translated feedback',async()=>{
   const p=await browser.newPage();
   try {
    await p.goto(url);
    await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.copiedText=text;}}}));
    await p.locator('[data-copy]').click();
    await p.waitForFunction(()=>document.querySelector('#copy-status').dataset.state==='success');
    assert.equal(await p.evaluate(()=>window.copiedText),'curl -L https://github.com/w8385/PokeTokenBar-yp/releases/latest/download/PokeTokenBar-yp-arm64.zip -o /tmp/PokeTokenBar-yp.zip && ditto -x -k /tmp/PokeTokenBar-yp.zip /Applications && xattr -dr com.apple.quarantine /Applications/PokeTokenBar.app && open /Applications/PokeTokenBar.app');
    await p.locator('#language').selectOption('ko');assert.match(await p.locator('#copy-status').innerText(),/복사했어요/);
    await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw Error('denied');}}}));
    await p.locator('[data-copy]').click();await p.waitForFunction(()=>document.querySelector('#copy-status').dataset.state==='error');
    assert.match(await p.locator('#copy-status').innerText(),/직접 선택/);
    assert.match(await p.evaluate(()=>getSelection().toString()),/curl -L https:\/\/github\.com\/w8385\/PokeTokenBar-yp\//);
    await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:undefined}));
    await p.locator('[data-copy]').click();await p.waitForFunction(()=>document.querySelector('#copy-status').dataset.state==='error');
    assert.equal(await p.locator('[data-copy]').isEnabled(),true);
   }finally{await p.close();}
  });
  await test('home: menu anchor to #install, guide tab keyboard',async()=>{
   const p=await browser.newPage({viewport:{width:375,height:812},reducedMotion:'reduce'});
   try {
    await p.goto(url);
    await p.locator('#menuBtn').click();await p.locator('#site-nav a[href="#install"]').click();
    assert.equal(await p.locator('#site-nav').isVisible(),false);
    await p.waitForFunction(()=>location.hash==='#install');
    const offset=await p.locator('#install').evaluate(x=>x.getBoundingClientRect().top);
    assert.ok(offset>=72,`Install hidden behind header: ${offset}`);
    assert.equal(await p.locator('#gtab-growth').isVisible(),true);await p.locator('#tab-growth').focus();
    await p.keyboard.press('ArrowRight');assert.equal(await p.locator('#tab-daily').getAttribute('aria-selected'),'true');
    assert.equal(await p.locator('#gtab-daily').isVisible(),true);assert.equal(await p.locator('#gtab-growth').isVisible(),false);
    await p.keyboard.press('End');assert.equal(await p.locator('#tab-collect').getAttribute('aria-selected'),'true');
    await p.keyboard.press('Home');assert.equal(await p.locator('#tab-growth').getAttribute('aria-selected'),'true');
    for(const anchor of ['top','features','companion','guide','install'])assert.equal(await p.locator('#'+anchor).count(),1,anchor);
   }finally{await p.close();}
  });
  await test('home without JavaScript: install command and every guide section show',async()=>{
   const p=await browser.newPage({javaScriptEnabled:false,viewport:{width:375,height:812}});
   try {
    await p.goto(url);
    assert.equal(await p.locator('[data-copy]').isVisible(),false);
    assert.match(await p.locator('#install-command').innerText(),/curl -L https:\/\/github\.com\/w8385\/PokeTokenBar-yp\//);
    for(const k of ['growth','daily','collect'])assert.equal(await p.locator('#gtab-'+k).isVisible(),true);
   }finally{await p.close();}
  });
  await test('blocked localStorage and missing image fallback do not block installation',async()=>{
   const p=await browser.newPage();
   try {
    await p.addInitScript(()=>Object.defineProperty(window,'localStorage',{get(){throw Error('blocked');}}));
    await p.route('**/assets/screenshot-home.png',route=>route.abort());
    await p.goto(url);assert.equal(await p.locator('#install-command').isVisible(),true);
    await p.locator('#language').selectOption('ja');assert.equal(await p.locator('html').getAttribute('lang'),'ja');
   }finally{await p.close();}
  });
  await test('reduced-motion uses still image; language and theme survive reload',async()=>{
   const p=await browser.newPage({reducedMotion:'reduce'});
   try {
    await p.goto(url);await p.locator('.pet-story').scrollIntoViewIfNeeded();
    await p.waitForFunction(()=>document.querySelector('.pet-story img').complete && document.querySelector('.pet-story img').naturalWidth>0);
    assert.match(await p.locator('.pet-story img').evaluate(x=>x.currentSrc),/floating-pet-still/);
    await p.locator('#demoBtn').click();assert.match(await p.locator('#pet-demo').getAttribute('src'),/floating-pet.gif/);
    await p.locator('#demoBtn').click();assert.match(await p.locator('#pet-demo').getAttribute('src'),/floating-pet-still/);
    await p.locator('#language').selectOption('ja');await p.locator('#themeBtn').click();await p.reload();
    assert.equal(await p.locator('html').getAttribute('lang'),'ja');assert.equal(await p.locator('html').getAttribute('data-theme'),'dark');
   }finally{await p.close();}
  });
  await test('16 linked tools follow the guide on home and close the usage page, in both themes',async()=>{
   const p=await browser.newPage({viewport:{width:375,height:812}});
   try {
    for(const target of [url,new URL('usage/',base).href]) {
     await p.goto(target);
     const links=p.locator('.provider-link');assert.equal(await links.count(),16);
     for(const theme of ['light','dark']) {
      if(theme==='dark')await p.locator('#themeBtn').click();
      await links.first().scrollIntoViewIfNeeded();
      await p.waitForFunction(()=>[...document.querySelectorAll('.provider-icon img')].every(i=>i.complete&&i.naturalWidth));
      for(const link of await links.all()) {assert.equal(await link.isVisible(),true);assert.match(await link.getAttribute('href'),/^https:\/\//);}
      await layout(p);
      if(target===url)await p.locator('#providers').screenshot({path:path.join(output,'providers-'+theme+'.png')});
      if(theme==='dark')await p.locator('#themeBtn').click();
     }
    }
    await p.goto(url);
    assert.equal(await p.locator('#providers').evaluate(x=>x.previousElementSibling.id),'guide');
    assert.equal(await p.locator('.provider-link').filter({hasText:'Kimi Code'}).getAttribute('href'),'https://www.kimi.com/code');
    await p.route('https://claude.com/**',r=>r.fulfill({status:200,body:'Official destination intercepted for navigation test'}));
    await p.locator('.provider-link').first().click();await p.waitForURL('https://claude.com/product/claude-code');
   }finally{await p.close();}
  });
  await test('language switching swaps text, alt text and native samples on every page',async()=>{
   const p=await browser.newPage({reducedMotion:'reduce'});
   try {
    for(const page of [...pages,notFound]) {
     await p.goto(new URL(page.path,base).href);
     for(const lang of ['ko','ja','en']) {
      await p.locator('#language').selectOption(lang);
      assert.deepEqual(await p.locator('[data-i18n-alt]').evaluateAll(es=>es.filter(e=>e.alt!==I18N[document.documentElement.lang][e.dataset.i18nAlt]).map(e=>e.dataset.i18nAlt)),[],page.id);
      assert.deepEqual(await p.locator('[data-i18n]').evaluateAll(es=>es.filter(e=>e.textContent.replace(/\n/g,'')!==I18N[document.documentElement.lang][e.dataset.i18n].replace(/\n/g,'')).map(e=>e.dataset.i18n)),[],page.id);
      const suffix=lang==='en'?'':'-'+lang;
      for(const src of await p.locator('[data-i18n-image]').evaluateAll(es=>es.map(e=>e.getAttribute('src'))))assert.ok(src.endsWith(suffix+'.png'),src);
      assert.equal(await p.locator('meta[name="description"]').getAttribute('content'),I18N[lang][page.id==='home'?'hero.lead':`meta.${page.id}.desc`]);
     }
    }
    await p.goto(url);
    assert.equal(await p.locator('.product-image img').getAttribute('src'),'assets/screenshot-home.png');
   }finally{await p.close();}
  });
  const swift=swiftSource();
  if(swift===null) {
   console.log('SKIP balance drift check: git or origin/main:Sources/PokeTokenBar/Core/CompanionModel.swift is unavailable');
   results.push({name:'BALANCE matches CompanionModel.swift on origin/main',status:'skip'});
  } else await test('BALANCE matches CompanionModel.swift on origin/main',async()=>{
   const p=await browser.newPage();
   try {await p.goto(url);assert.deepEqual(await p.evaluate(()=>BALANCE),appBalance(swift));}finally{await p.close();}
  });
  await test('cost table and number copy follow BALANCE in every language',async()=>{
   const p=await browser.newPage();
   try {
    await p.goto(url);
    assert.deepEqual(await p.evaluate(()=>[...document.querySelectorAll('tr[data-rarity]')].flatMap(row=>{
     const total=BALANCE.graduationTotal[row.dataset.rarity];
     const want=[1,2,3].map(i=>formatTokens(total*i/6)).concat(formatTokens(total));
     const got=[...row.querySelectorAll('td.num')].map(td=>td.textContent);
     return want.join()===got.join()?[]:[{rarity:row.dataset.rarity,want,got}];
    })),[]);
    assert.equal(await p.locator('tr[data-rarity]').count(),4);
    const missing=await p.evaluate(()=>{
     const b=BALANCE, pct=x=>Math.round(x*100)+'%';
     const expected={
      'journey.hatchDesc':[formatTokens(b.eggHatchThreshold)],
      'modes.timeRate':[formatTokens(b.timeTokensPerActiveHour),formatTokens(b.timeWalletTokensPerActiveHour)],
      'modes.timeIdle':[String(b.timeIdleLimitSeconds/60),String(b.timeMaxStepSeconds/60)],
      'modes.hint':[String(b.idleTokenHintAfterSeconds/86400)],
      'modes.clickD':[formatTokens(b.tokensPerClick),String(b.clickMinIntervalSeconds),(Math.round((b.graduationTotal.common+b.eggHatchThreshold)/b.tokensPerClick/100)*100).toLocaleString('en')],
      'p1.t':b.difficultyRange.map(pct),
      'k3.d':[formatTokens(b.graduationTotal.common),formatTokens(b.graduationTotal.legendary)]
     };
     return Object.entries(I18N).flatMap(([lang,dict])=>Object.entries(expected).flatMap(([key,parts])=>parts.filter(part=>!dict[key].includes(part)).map(part=>`${lang} ${key}: ${part}`)));
    });
    assert.deepEqual(missing,[]);
   }finally{await p.close();}
  });
  await test('growth animation play, pause and reduced motion remain available',async()=>{
   const p=await browser.newPage({reducedMotion:'reduce'});
   try {
    await p.goto(url);
    assert.equal(await p.locator('#growth-motion').getAttribute('aria-pressed'),'false');
    await p.locator('#growth-motion').click();
    assert.equal(await p.locator('#growth-motion').getAttribute('aria-pressed'),'true');
    for(const src of await p.locator('[data-growth-sprite]').evaluateAll(es=>es.map(e=>e.getAttribute('src'))))assert.match(src,/\.gif$/);
    await p.locator('#growth-motion').click();
    assert.equal(await p.locator('#growth-motion').getAttribute('aria-pressed'),'false');
    for(const src of await p.locator('[data-growth-sprite]').evaluateAll(es=>es.map(e=>e.getAttribute('src'))))assert.match(src,/\.png$/);
   }finally{await p.close();}
  });
  await test('every same-page link has a target and ZIP uses latest release',async()=>{
   const p=await browser.newPage();
   try {
    for(const page of [...pages,notFound]) {
     await p.goto(new URL(page.path,base).href);
     assert.deepEqual(await p.locator('a[href^="#"]').evaluateAll(as=>as.filter(a=>!document.getElementById(a.hash.slice(1))).map(a=>a.hash)),[],page.id);
    }
    await p.goto(url);
    assert.equal(await p.locator('a[href$="PokeTokenBar-yp-arm64.zip"]').getAttribute('href'),'https://github.com/w8385/PokeTokenBar-yp/releases/latest/download/PokeTokenBar-yp-arm64.zip');
   }finally{await p.close();}
  });
 }catch(error){problems.push({name:'harness',error:error.stack});}
 finally {
  if(browser)await browser.close();server.close();
  fs.writeFileSync(path.join(output,'verification.json'),JSON.stringify({results,problems},null,2));
  console.log(`${results.filter(r=>r.status==='pass').length}/${results.length} checks passed`);
  if(problems.length){console.error(JSON.stringify(problems,null,2));process.exitCode=1;}
 }
})();
