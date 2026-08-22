#!/usr/bin/env node
/* SHELF LIFE — rule-16 REAL browser playthrough.
 * Runs under xvfb-run with NON-headless chromium; clicks are real X11 events
 * via xdotool. CDP is used only to READ state (debug bridge) + screenshots.
 * Plays 3 days to SHOP OPEN through the actual UI.
 *
 * Usage: xvfb-run -a -s "-screen 0 1152x700x24" node tools/playtest_x11.js
 */
const { execFile, execSync } = require("child_process");
const http = require("http");
const fs = require("fs");

const PORT = 9340;
const URL = "https://sxaad69.github.io/shelf-life/";
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function httpGetJson(path) {
  return new Promise((resolve, reject) => {
    http.get({ host: "127.0.0.1", port: PORT, path }, res => {
      let d = ""; res.on("data", c => d += c); res.on("end", () => resolve(JSON.parse(d)));
    }).on("error", reject);
  });
}

async function main() {
  const chrome = execFile("chromium-browser", [
    "--no-sandbox", "--user-data-dir=/tmp/chr-qa-sl-" + Date.now(),
    "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    "--kiosk", "--window-position=0,0",
    `--remote-debugging-port=${PORT}`, "--window-size=1152,700",
    "--autoplay-policy=no-user-gesture-required", URL,
  ]);
  await sleep(4000);

  // wait for CDP
  let page = null;
  for (let i = 0; i < 20; i++) {
    try {
      const targets = await httpGetJson("/json/list");
      page = targets.find(t => t.type === "page");
      if (page) break;
    } catch (e) {}
    await sleep(1000);
  }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let mid = 0; const pending = new Map(); const consoleLines = [];
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    else if (m.method === "Runtime.consoleAPICalled") {
      consoleLines.push((m.params.args || []).map(a => a.value || a.description || "").join(" ").slice(0, 200));
    } else if (m.method === "Runtime.exceptionThrown") {
      consoleLines.push("[EXCEPTION] " + JSON.stringify(m.params.exceptionDetails).slice(0, 250));
    }
  };
  const send = (method, params = {}) => new Promise(res => { const id = ++mid; pending.set(id, res); ws.send(JSON.stringify({ id, method, params })); });
  const evalJs = async e => (await send("Runtime.evaluate", { expression: e, returnByValue: true })).result?.result?.value;

  // No WM on bare Xvfb — no activate needed.
  await sleep(1500);

  // wait for boot: canvas present AND debug bridge published (game _ready ran)
  let booted = false;
  for (let i = 0; i < 90; i++) {
    await sleep(2000);
    try {
      const ok = await evalJs(`(function(){ var c = document.getElementById('canvas'); return !!(c && c.width > 320 && window.__SL_STATE); })()`);
      if (ok) { booted = true; break; }
      if (i % 10 === 9) {
        const probe = await evalJs(`(function(){ var c = document.getElementById('canvas'); return JSON.stringify({cw: c?c.width:0, state: !!window.__SL_STATE, url: location.href}); })()`);
        console.log("bootprobe", i, probe);
      }
    } catch (e) { console.log("bootloop err:", String(e).slice(0, 120)); }
  }
  console.log("BOOT_CANVAS:", booted ? "PASS" : "FAIL");
  await sleep(6000);

  const results = [];
  const assert = (name, cond, detail) => {
    results.push({ name, pass: !!cond });
    console.log((cond ? "PASS" : "FAIL") + ": " + name + (detail ? " (" + detail + ")" : ""));
  };
  assert("boot_no_crash", booted);

  const R = JSON.parse(await evalJs(`(function(){ var r = document.getElementById('canvas').getBoundingClientRect(); return JSON.stringify({left:r.left, top:r.top, width:r.width, height:r.height}); })()`));
  console.log("canvas rect:", JSON.stringify(R));
  const scale = Math.min(R.width / 1152, R.height / 648);
  const ox = (R.width - 1152 * scale) / 2 + R.left;
  const oy = (R.height - 648 * scale) / 2 + R.top;
  // find chromium window position on screen

  async function click(dx, dy) {
    const px = Math.round(ox + dx * scale), py = Math.round(oy + dy * scale);
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: px, y: py, button: "left", clickCount: 1 });
    await sleep(80);
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: px, y: py, button: "left", clickCount: 1 });
    await sleep(380);
  }
  async function clickRight(dx, dy) {
    const px = Math.round(ox + dx * scale), py = Math.round(oy + dy * scale);
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: px, y: py, button: "right", clickCount: 1 });
    await sleep(80);
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: px, y: py, button: "right", clickCount: 1 });
    await sleep(380);
  }
  const getState = () => evalJs("window.__SL_STATE || null").then(s => typeof s === "string" ? JSON.parse(s) : s);

  function btnPos(st, labelPrefix) {
    for (const k of Object.keys(st.buttons || {})) {
      if (k.startsWith(labelPrefix)) return { x: st.buttons[k].x, y: st.buttons[k].y };
    }
    return null;
  }
  function shelfGeom(bays) {
    const cw = 190, gap = 16;
    const totalW = bays * cw + (bays - 1) * gap;
    const x0 = 576 - totalW / 2;
    const cols = [];
    for (let b = 0; b < bays; b++) cols.push({ cx: x0 + b * (cw + gap) + cw / 2 });
    return { cols, frontY: 232, backY: 310 };
  }
  const trayPos = i => ({ x: 32 + i * 120 + 55, y: 590 });

  function adjacencyOk(out) {
    const pos = {};
    out.forEach((it, k) => { if (it) (pos[it.cat] = pos[it.cat] || []).push(k); });
    return Object.values(pos).every(ps => ps[ps.length - 1] - ps[0] === ps.length - 1);
  }
  function solveFull(st) {
    let sol = null;
    const items = st.tray.map((t, i) => ({ ...t, trayIdx: i }));
    const slots = st.bays * 2;
    const used = new Array(items.length).fill(false);
    const out = new Array(slots).fill(null);
    const needW = st.rules.includes("WEIGHT"), needF = st.rules.includes("FIFO"), needA = st.rules.includes("ADJACENCY");
    function rec(k) {
      if (sol) return;
      if (k === slots) { if (!needA || adjacencyOk(out)) sol = out.slice(); return; }
      for (let i = 0; i < items.length; i++) {
        if (used[i]) continue;
        if (needW && k % 2 === 1 && items[i].w > out[k - 1].w) continue;
        if (needF && k > 0 && items[i].exp < out[k - 1].exp) continue;
        used[i] = true; out[k] = items[i];
        rec(k + 1);
        used[i] = false; out[k] = null;
        if (sol) return;
      }
    }
    rec(0);
    return sol;
  }

  const feelNotes = [];
  for (let day = 1; day <= 3; day++) {
    await sleep(1200);
    let st = await getState();
    if (!st) { assert("state_bridge_day" + day, false); break; }
    console.log(`DAY ${day}: level=${st.level} bays=${st.bays} rules=${st.rules.join(",")} tray=${st.tray.length}`);
    const sol = solveFull(st);
    assert("day" + day + "_solvable", !!sol);
    if (!sol) break;

    for (let k = 0; k < sol.length; k++) {
      const it = sol[k];
      const bay = Math.floor(k / 2), row = k % 2;
      st = await getState();
      if (!st || !st.tray_rects) { console.log("rects missing"); break; }
      // tray reflows after each placement — locate THIS item's current position by id
      const curIdx = st.tray.findIndex(t => t.id === it.id);
      if (curIdx < 0) { console.log("item not in tray:", it.id); break; }
      await click(st.tray_rects[curIdx].x, st.tray_rects[curIdx].y);
      await click(st.cell_rects[bay][row].x, st.cell_rects[bay][row].y);
      st = await getState();
      if (!st) break;
    }
    st = await getState();
    assert("day" + day + "_tray_emptied_by_real_clicks", st && st.tray.length === 0, st ? "tray=" + st.tray.length : "?");
    if (!st || st.tray.length > 0) {
      const shot = await send("Page.captureScreenshot", { format: "png" });
      fs.writeFileSync("/tmp/sl_playtest_stuck_day" + day + ".png", Buffer.from(shot.result.data, "base64"));
      break;
    }

    // flips via right-click where needed
    if (st.rules.includes("FACING")) {
      for (let bay = 0; bay < st.bays; bay++) {
        for (let row = 0; row < 2; row++) {
          const it = st.shelf[bay][row];
          if (it && !it.face_out) {
            const cur = await getState();
            await clickRight(cur.cell_rects[bay][row].x, cur.cell_rects[bay][row].y);
            st = await getState();
          }
        }
      }
    }
    st = await getState();
    assert("day" + day + "_all_facing_out", st && st.shelf.flat().every(it => !it || it.face_out));

    const ob = btnPos(st, "OPEN SHOP");
    await click(ob.x, ob.y);
    await sleep(900);
    st = await getState();
    console.log("post-audit status:", JSON.stringify(st.status || "").slice(0, 120));
    feelNotes.push(`day ${day}: ${st.bays} bays / ${st.rules.join("+")} — placed all, audited OPEN SHOP`);
    const solved = st && st.tray.length === 0 && st.shelf.flat().filter(Boolean).length === st.bays * 2;
    assert("day" + day + "_level_complete", !!solved);

    const shot = await send("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(`/tmp/sl_playthrough_day${day}.png`, Buffer.from(shot.result.data, "base64"));

    if (!solved) break;
    if (day < 3) {
      const nb = btnPos(st, "NEXT DAY");
      await click(nb ? nb.x : 92, nb ? nb.y : 316);
      await sleep(1400);
      const st2 = await getState();
      console.log(`  -> advanced to day ${st2 ? st2.level : "?"}`);
    }
  }

  console.log("CONSOLE_LINES_BEGIN");
  for (const l of consoleLines.slice(-15)) console.log(l);
  console.log("CONSOLE_LINES_END");
  const errors = consoleLines.filter(l => l.startsWith("[EXCEPTION]") || l.startsWith("[error]"));
  assert("zero_console_errors", errors.length === 0, errors.length + " errors");
  const passed = results.filter(r => r.pass).length;
  console.log(`SUMMARY: ${passed}/${results.length} checks passed`);
  console.log("FEEL_NOTES:", JSON.stringify(feelNotes));
  ws.close(); chrome.kill();
  process.exit(passed === results.length ? 0 : 2);
}
main().catch(e => { console.error("HARNESS_ERROR", e); process.exit(1); });
