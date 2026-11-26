const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const dir = __dirname;
const bridge = fs.readFileSync(path.join(dir,'bridge.js'),'utf8');
const ytBrowse = fs.readFileSync(path.join(dir,'yt_browse.js'),'utf8');
const ytPlayer = fs.readFileSync(path.join(dir,'yt_player.js'),'utf8');
const video = fs.readFileSync(path.join(dir,'test.webm'));
let failures=0; const check=(n,c,x)=>{console.log(`${c?'PASS':'FAIL'}  ${n}${x!==undefined?'  '+JSON.stringify(x):''}`); if(!c)failures++;};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const HTML = (extra='')=>`<!doctype html><title>YT mock</title><body>
<header class="mobile-topbar-header" id="hdr" style="height:48px">top</header>
<ytm-pivot-bar-renderer id="pivot">bottom nav</ytm-pivot-bar-renderer>
<a id="vid" href="/watch?v=abc123"><span id="inner">Video title</span></a>
<a id="short" href="/shorts/xyz789">short</a>
<a id="yb" href="https://youtu.be/QQQ111">youtu.be</a>
<a id="chan" href="/@somechannel">channel</a>
<a id="ext" href="https://example.org/">ext</a>
<video id="v" src="/v.webm" playsinline width=200></video>${extra}`;
async function mk(browser, script, url){
  const ctx = await browser.newContext({ viewport:{width:390,height:844}, isMobile:true, hasTouch:true });
  const page = await ctx.newPage();
  await page.route('https://m.youtube.com/**', async r=>{
    const u=new URL(r.request().url());
    if(u.pathname==='/v.webm') return r.fulfill({status:200, contentType:'video/webm', body:video});
    return r.fulfill({status:200, contentType:'text/html', body:HTML()});
  });
  await page.addInitScript(()=>{ window.__nav=[]; window.__msgs=[]; window.webkit={messageHandlers:{kvNav:{postMessage:m=>window.__nav.push(m)},kvMedia:{postMessage:m=>window.__msgs.push(m)}}}; });
  await page.addInitScript(bridge); await page.addInitScript(script);
  await page.goto(url); return page;
}
(async()=>{
  const browser = await chromium.launch({args:['--autoplay-policy=no-user-gesture-required']});
  // ---- browse role
  let page = await mk(browser, ytBrowse, 'https://m.youtube.com/');
  const vis = await page.evaluate(()=>({hdr:getComputedStyle(document.getElementById('hdr')).display, pivot:getComputedStyle(document.getElementById('pivot')).display}));
  check('YouTube header + bottom bar hidden (native bars replace them)', vis.hdr==='none'&&vis.pivot==='none', vis);
  await page.click('#inner'); await sleep(150);
  let nav = await page.evaluate(()=>window.__nav.slice());
  check('tap on a video link is intercepted -> native "watch" request', nav.length===1 && nav[0].type==='watch' && /watch\?v=abc123/.test(nav[0].url), nav);
  check('page did NOT navigate away (browse stays put)', page.url()==='https://m.youtube.com/');
  await page.click('#short'); await sleep(100);
  await page.evaluate(()=>document.getElementById('yb').click()); await sleep(100);
  nav = await page.evaluate(()=>window.__nav.slice());
  check('shorts + youtu.be links intercepted', nav.some(m=>/shorts\/xyz789/.test(m.url)) && nav.some(m=>/youtu\.be\/QQQ111/.test(m.url)), nav.map(m=>m.url));
  const before = (await page.evaluate(()=>window.__nav.length));
  await page.evaluate(()=>{ const a=document.getElementById('chan'); a.addEventListener('click',e=>{e.preventDefault(); window.__chanClicked=true;}); a.click(); });
  check('channel link NOT intercepted (normal YouTube navigation)', (await page.evaluate(()=>window.__nav.length))===before && await page.evaluate(()=>window.__chanClicked===true));
  await page.close();
  // ---- browse safety net: unmuted video playing on a /watch URL is paused and redirected
  page = await mk(browser, ytBrowse, 'https://m.youtube.com/watch?v=zzz');
  await page.evaluate(()=>{const v=document.getElementById('v'); v.muted=false; return v.play();}); await sleep(800);
  nav = await page.evaluate(()=>window.__nav.slice());
  check('audible playback in browse view is paused and redirected to player', nav.some(m=>m.type==='watch') && await page.evaluate(()=>document.getElementById('v').paused), nav);
  await page.close();
  // ---- player role: autoplay
  page = await mk(browser, ytPlayer, 'https://m.youtube.com/watch?v=abc123'); await sleep(3500);
  const st = await page.evaluate(()=>{const v=document.getElementById('v'); return {paused:v.paused, t:v.currentTime};});
  check('player view autoplays (no tap needed)', !st.paused && st.t>0.5, st);
  const msgs = await page.evaluate(()=>window.__msgs.filter(m=>m.type==='state'));
  check('player view reports state to native', msgs.length>0);
  await page.close();
  // ---- media error reporting
  page = await mk(browser, ytPlayer, 'https://m.youtube.com/watch?v=err');
  await page.evaluate(()=>{const a=document.createElement('video'); a.id='bad'; a.src='/missing.webm'; document.body.appendChild(a); a.load();}); await sleep(1200);
  const errs = await page.evaluate(()=>window.__msgs.filter(m=>m.type==='mediaError'));
  check('failed media is reported (type=mediaError with code)', errs.length>0 && errs[0].code>0, errs[0]);
  const diag = await page.evaluate(()=>window.__msgs.filter(m=>m.type==='diag'));
  check('capability diag posted once per top frame', diag.length===1 && 'mse' in diag[0], diag[0]);
  await browser.close();
  console.log(failures? failures+' FAILURE(S)':'\nALL YOUTUBE SCRIPT TESTS PASSED'); process.exit(failures?1:0);
})().catch(e=>{console.error('HARNESS',e);process.exit(2);});
