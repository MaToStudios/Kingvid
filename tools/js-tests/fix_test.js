const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const dir = __dirname;
const bridge = fs.readFileSync(path.join(dir,'bridge.js'),'utf8');
const ytPlayer = fs.readFileSync(path.join(dir,'yt_player.js'),'utf8');
const video = fs.readFileSync(path.join(dir,'test.webm'));
let failures=0; const check=(n,c,x)=>{console.log(`${c?'PASS':'FAIL'}  ${n}${x!==undefined?'  '+JSON.stringify(x):''}`); if(!c)failures++;};
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
  const browser = await chromium.launch({args:['--autoplay-policy=no-user-gesture-required']});
  const ctx = await browser.newContext({viewport:{width:390,height:844}});
  const page = await ctx.newPage();
  await page.route('https://m.youtube.com/**', r=>{
    const u=new URL(r.request().url());
    if(u.pathname==='/v.webm') return r.fulfill({status:200, contentType:'video/webm', body:video});
    return r.fulfill({status:200, contentType:'text/html', body:'<!doctype html><video id="v" src="/v.webm" playsinline></video>'});
  });
  await page.addInitScript(()=>{ window.__msgs=[]; window.webkit={messageHandlers:{kvNav:{postMessage(){}} ,kvMedia:{postMessage:m=>window.__msgs.push(m)}}}; });
  await page.addInitScript(bridge); await page.addInitScript(ytPlayer);
  await page.goto('https://m.youtube.com/watch?v=abc');
  await sleep(2500);
  check('video autoplays and KEEPS playing (no stop after ~0.5s)', await page.evaluate(async()=>{const v=document.getElementById('v'); const t0=v.currentTime; await new Promise(r=>setTimeout(r,2500)); return !v.paused && v.currentTime>t0+2;}));
  // "hold" (audio interruption) must not pause the page
  await page.evaluate(()=>__kv.cmd('hold')); await sleep(600);
  check('cmd(hold) does NOT pause the video', !(await page.evaluate(()=>document.getElementById('v').paused)));
  // ...but it stops background auto-resume from fighting a real interruption
  await page.evaluate(()=>{__kv.setBg(true); document.getElementById('v').pause();}); await sleep(3500);
  check('after hold, a background pause is not fought (call/Siri respected)', await page.evaluate(()=>document.getElementById('v').paused));
  await page.evaluate(()=>{__kv.setBg(false); __kv.cmd('play');}); await sleep(800);
  check('play after hold resumes', !(await page.evaluate(()=>document.getElementById('v').paused)));
  // native pause from KingVid controls must stick (autoplay helper must not undo it)
  await page.evaluate(()=>__kv.cmd('pause')); await sleep(3000);
  check('native pause sticks for 3s (autoplay helper does not restart it)', await page.evaluate(()=>document.getElementById('v').paused));
  await browser.close();
  console.log(failures? failures+' FAILURE(S)':'\nALL FIX TESTS PASSED'); process.exit(failures?1:0);
})().catch(e=>{console.error('HARNESS',e);process.exit(2);});
