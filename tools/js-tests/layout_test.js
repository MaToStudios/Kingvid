const { chromium } = require('playwright');
const fs=require('fs'), path=require('path'); const dir=__dirname;
const bridge=fs.readFileSync(path.join(dir,'bridge.js'),'utf8'), ytPlayer=fs.readFileSync(path.join(dir,'yt_player.js'),'utf8');
const video=fs.readFileSync(path.join(dir,'test.webm'));
let failures=0; const check=(n,c,x)=>{console.log(`${c?'PASS':'FAIL'}  ${n}${x!==undefined?'  '+JSON.stringify(x):''}`); if(!c)failures++;};
// Mirrors m.youtube.com watch DOM (from the real-page recon): sticky header in ytm-app, player container as a body child,
// YouTube-style inline sizing on the player/video, its own control layer, plus page content below.
const PAGE=`<!doctype html><html class="sticky-player watch-scroll"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>#player-container-id{position:sticky;top:48px} .player-size{padding-bottom:56.25%;position:relative} ytm-app{display:block}</style>
<script>var ytInitialPlayerResponse={"videoDetails":{"videoId":"abcdefghijk","title":"Mock title","author":"Mock Channel","channelId":"UC1","viewCount":"1234","shortDescription":"desc","isLiveContent":false},"microformat":{"playerMicroformatRenderer":{"publishDate":"2024-01-02"}},"streamingData":{"huge":"x"}};
var ytInitialData={"contents":{"x":[{"videoWithContextRenderer":{"videoId":"zzzzzzzzzzz","headline":{"runs":[{"text":"Related"}]}}}]}};</script></head>
<body><ytm-app><header class="mobile-topbar-header" style="height:48px;position:sticky;top:0">YouTube header</header></ytm-app>
<div id="player-container-id" class="player-container sticky-player"><div id="player" class="player-api player-size">
<div id="movie_player" class="html5-video-player" style="width:390px;height:219px"><div class="html5-video-container">
<video class="video-stream html5-main-video" src="/v.webm" style="width:390px;height:219px;left:0;top:0" playsinline></video></div>
<ytm-watch-player-controls id="ytctl"><div class="player-controls-content" style="height:100px">YT controls</div></ytm-watch-player-controls>
</div></div></div>
<div id="below" style="height:2000px">description / comments</div></body></html>`;
(async()=>{
  const b=await chromium.launch({args:['--autoplay-policy=no-user-gesture-required']});
  for (const vp of [{width:390,height:219},{width:430,height:242},{width:844,height:390}]) {
    const ctx=await b.newContext({viewport:vp}); const p=await ctx.newPage();
    await p.route('https://m.youtube.com/**', r=>{ const u=new URL(r.request().url()); return u.pathname==='/v.webm'? r.fulfill({status:200,contentType:'video/webm',body:video}) : r.fulfill({status:200,contentType:'text/html',body:PAGE}); });
    await p.addInitScript(()=>{ window.__nav=[]; window.__msgs=[]; window.webkit={messageHandlers:{kvNav:{postMessage:m=>window.__nav.push(m)},kvMedia:{postMessage:m=>window.__msgs.push(m)}}}; });
    await p.addInitScript(bridge); await p.addInitScript(ytPlayer);
    await p.goto('https://m.youtube.com/watch?v=abcdefghijk'); await p.waitForTimeout(2500);
    const r=await p.evaluate(()=>{ const v=document.querySelector('video').getBoundingClientRect(); const c=document.getElementById('ytctl'); const h=document.querySelector('header');
      return {v:[Math.round(v.x),Math.round(v.y),Math.round(v.width),Math.round(v.height)], vw:innerWidth, vh:innerHeight, ctl:getComputedStyle(c).display, header:getComputedStyle(h.parentElement).visibility, scroll: document.documentElement.scrollHeight<=innerHeight+1 || getComputedStyle(document.body).overflow==='hidden'}; });
    check(`video fills the whole ${vp.width}x${vp.height} view (no bars, no header offset)`, r.v[0]===0&&r.v[1]===0&&r.v[2]===r.vw&&r.v[3]===r.vh, r.v);
    check(`YouTube's own controls hidden (${vp.width}x${vp.height})`, r.ctl==='none');
    check(`page header/content hidden behind video (${vp.width}x${vp.height})`, r.header==='hidden' && r.scroll);
    if (vp.width===390) {
      const nav=await p.evaluate(()=>window.__nav.filter(m=>m.type==='watchData'));
      check('watchData posted once for the current video', nav.length===1 && nav[0].videoId==='abcdefghijk');
      check('watchData omits heavy streamingData', nav[0] && !nav[0].playerResponse.includes('streamingData') && nav[0].playerResponse.includes('Mock title'));
      check('watchData includes related videos JSON', nav[0] && nav[0].initialData.includes('videoWithContextRenderer'));
      const st=await p.evaluate(()=>window.__msgs.filter(m=>m.type==='state').pop());
      check('state reports video dimensions for aspect ratio', st && st.vw===320 && st.vh===180, st && [st.vw,st.vh]);
      check('state reports muted + ad flags', st && st.muted===false && st.ad===false && st.adSkip===false);
      await p.evaluate(()=>{ const v=document.querySelector('video'); v.muted=true; }); await p.waitForTimeout(400);
      await p.evaluate(()=>__kv.cmd('unmute')); 
      check('cmd(unmute) unmutes', await p.evaluate(()=>!document.querySelector('video').muted));
      await p.evaluate(()=>{ document.getElementById('movie_player').classList.add('ad-showing'); const s=document.createElement('button'); s.className='ytp-ad-skip-button-modern'; s.textContent='Skip'; s.onclick=()=>window.__skipped=true; document.getElementById('movie_player').appendChild(s); __kv.report(); });
      const ad=await p.evaluate(()=>window.__msgs.filter(m=>m.type==='state').pop());
      check('ad + skippable detected', ad.ad===true && ad.adSkip===true);
      await p.evaluate(()=>__kv.cmd('skipAd'));
      check('cmd(skipAd) presses YouTube\'s skip button', await p.evaluate(()=>window.__skipped===true));
    }
    await ctx.close();
  }
  await b.close();
  console.log(failures? failures+' FAILURE(S)':'\nALL LAYOUT TESTS PASSED'); process.exit(failures?1:0);
})().catch(e=>{console.error('HARNESS',e);process.exit(2);});
