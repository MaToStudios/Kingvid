// Behavioural test of the injected media bridge (KingVid/Media/MediaScripts.swift) in headless Chromium.
// Mocks webkit.messageHandlers.kvMedia so we can see exactly what native code would receive.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const http = require('http');

const dir = __dirname;
const bridge = fs.readFileSync(path.join(dir, 'bridge.js'), 'utf8');

const server = http.createServer((req, res) => {
  const f = path.join(dir, req.url.split('?')[0].replace(/^\//, '') || 'page.html');
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  const type = f.endsWith('.html') ? 'text/html' : f.endsWith('.webm') ? 'video/webm' : 'application/octet-stream';
  const stat = fs.statSync(f);
  const range = req.headers.range;
  if (range) {
    const [s, e] = range.replace('bytes=', '').split('-');
    const start = parseInt(s, 10), end = e ? parseInt(e, 10) : stat.size - 1;
    res.writeHead(206, { 'Content-Type': type, 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1 });
    fs.createReadStream(f, { start, end }).pipe(res);
  } else {
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': stat.size, 'Accept-Ranges': 'bytes' });
    fs.createReadStream(f).pipe(res);
  }
}).listen(0);

let failures = 0;
function check(name, cond, extra) {
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${extra !== undefined ? '  ' + JSON.stringify(extra) : ''}`);
  if (!cond) failures++;
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const ctx = await browser.newContext({
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
    viewport: { width: 390, height: 844 },
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  await page.exposeFunction('__native', () => {});
  await page.addInitScript(() => {
    window.__msgs = [];
    window.webkit = { messageHandlers: { kvMedia: { postMessage: (m) => window.__msgs.push(m) } } };
  });
  await page.addInitScript(bridge);
  await page.goto(`http://localhost:${port}/page.html`);

  // --- visibility spoofing
  const vis = await page.evaluate(() => ({ hidden: document.hidden, state: document.visibilityState, focus: document.hasFocus() }));
  check('visibility spoofed (hidden=false, visible, hasFocus)', vis.hidden === false && vis.state === 'visible' && vis.focus === true, vis);

  // --- play -> state messages
  await page.evaluate(() => document.getElementById('v').play());
  await sleep(1500);
  let msgs = await page.evaluate(() => window.__msgs.slice());
  const playing = msgs.filter(m => m.paused === false);
  check('bridge posts "playing" state', playing.length > 0, playing[0] && { paused: playing[0].paused, dur: playing[0].duration, isVideo: playing[0].isVideo });
  check('duration reported (~60s)', playing.some(m => m.duration > 55 && m.duration < 65));
  const pos = await page.evaluate(() => document.getElementById('v').currentTime);
  check('video actually advancing', pos > 0.8, pos);
  check('host/url reported', msgs.some(m => m.host === 'localhost' && /page\.html/.test(m.url)));

  // --- commands
  await page.evaluate(() => __kv.cmd('pause'));
  await sleep(300);
  check('cmd(pause) pauses', await page.evaluate(() => document.getElementById('v').paused));
  await page.evaluate(() => __kv.cmd('seek', 30));
  await sleep(300);
  check('cmd(seek 30)', Math.abs(await page.evaluate(() => document.getElementById('v').currentTime) - 30) < 1);
  await page.evaluate(() => __kv.cmd('skip', 15));
  await sleep(300);
  check('cmd(skip +15)', Math.abs(await page.evaluate(() => document.getElementById('v').currentTime) - 45) < 1.5);
  await page.evaluate(() => __kv.cmd('play'));
  await sleep(600);
  check('cmd(play) resumes', !(await page.evaluate(() => document.getElementById('v').paused)));
  await page.evaluate(() => __kv.cmd('rate', 1.5));
  check('cmd(rate 1.5)', (await page.evaluate(() => document.getElementById('v').playbackRate)) === 1.5);

  // --- background auto-resume: page/WebKit pauses video while backgrounded
  await page.evaluate(() => __kv.setBg(true));
  await page.evaluate(() => document.getElementById('v').pause());   // simulated system/page pause
  await sleep(600);
  check('auto-resume after external pause in background', !(await page.evaluate(() => document.getElementById('v').paused)));

  // --- user pause in background must NOT be resumed
  await page.evaluate(() => __kv.cmd('pause'));
  await sleep(3500);
  check('user pause in background is respected (no fight)', await page.evaluate(() => document.getElementById('v').paused));

  // --- resume after user press play
  await page.evaluate(() => __kv.cmd('play'));
  await sleep(500);
  check('play after user pause works in background', !(await page.evaluate(() => document.getElementById('v').paused)));

  // --- foreground: external pause is reported, not fought
  await page.evaluate(() => __kv.setBg(false));
  await page.evaluate(() => { window.__msgs.length = 0; document.getElementById('v').pause(); });
  await sleep(500);
  const fg = await page.evaluate(() => window.__msgs.slice());
  check('foreground pause is reported as paused', fg.some(m => m.paused === true));
  check('foreground pause is not auto-resumed', await page.evaluate(() => document.getElementById('v').paused));

  // --- detached new Audio() element is tracked
  await page.evaluate(() => { window.__msgs.length = 0; window.__a = new Audio('test.webm'); window.__a.play(); });
  await sleep(1200);
  const au = await page.evaluate(() => window.__msgs.slice());
  check('detached new Audio() playback is tracked', au.some(m => m.paused === false && m.isVideo === false), au.length);

  // --- mediaSession metadata + handlers captured
  await page.evaluate(() => {
    navigator.mediaSession.metadata = new MediaMetadata({ title: 'Song Title', artist: 'The Artist', artwork: [{ src: '/art128.png', sizes: '128x128' }, { src: '/art512.png', sizes: '512x512' }] });
    window.__nextCalled = 0;
    navigator.mediaSession.setActionHandler('nexttrack', () => { window.__nextCalled++; });
    window.__a.pause(); window.__a.play();
  });
  await sleep(800);
  const md = await page.evaluate(() => window.__msgs.filter(m => m.paused === false).pop());
  check('mediaSession title/artist picked up', md && md.title === 'Song Title' && md.artist === 'The Artist', md && { t: md.title, a: md.artist });
  check('largest artwork chosen & absolute', md && /art512\.png$/.test(md.artwork) && md.artwork.startsWith('http'), md && md.artwork);
  check('hasNext reflects site handler', md && md.hasNext === true);
  await page.evaluate(() => __kv.cmd('next'));
  check('cmd(next) invokes site handler', (await page.evaluate(() => window.__nextCalled)) === 1);

  // --- the bridge must not break the page itself
  check('no page errors', errors.length === 0, errors);

  await browser.close();
  server.close();
  console.log(failures === 0 ? '\nALL BRIDGE TESTS PASSED' : `\n${failures} FAILURE(S)`);
  process.exit(failures ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
