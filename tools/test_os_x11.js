#!/usr/bin/env node
/* Focused: boot game under xvfb kiosk, xdotool-click OPEN SHOP, screenshot + state. */
const { execFile, execSync } = require("child_process");
const http = require("http");
const fs = require("fs");
const PORT = 9344;
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
    "--no-sandbox", "--user-data-dir=/tmp/chr-os",
    "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    "--kiosk", "--window-position=0,0", "--remote-debugging-port=" + PORT,
    "https://sxaad69.github.io/shelf-life/",
  ]);
  await sleep(5000);
  const page = (await httpGetJson("/json/list")).find(t => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let mid = 0; const pending = new Map(); const consoleLines = [];
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } else if (m.method === "Runtime.consoleAPICalled") { consoleLines.push((m.params.args || []).map(a => a.value || "").join(" ").slice(0, 150)); } };
  const send = (method, params = {}) => new Promise(res => { const id = ++mid; pending.set(id, res); ws.send(JSON.stringify({ id, method, params })); });
  const evalJs = async e => (await send("Runtime.evaluate", { expression: e, returnByValue: true })).result?.result?.value;
  await send("Runtime.enable");

  for (let i = 0; i < 90; i++) {
    await sleep(2000);
    if (await evalJs(`!!(window.__SL_STATE)`) === true) break;
  }
  const R = JSON.parse(await evalJs(`JSON.stringify(document.getElementById('canvas').getBoundingClientRect())`));
  console.log("rect:", JSON.stringify(R));
  execSync("xdotool mousemove 380 300 sleep 0.1 click 1"); // OPEN SHOP at design(346,316)*~1
  await sleep(900);
  const shot = await send("Page.captureScreenshot", { format: "png" });
  fs.writeFileSync("/tmp/sl_x11_openshop.png", Buffer.from(shot.result.data, "base64"));
  console.log("console:", consoleLines.slice(-4));
  ws.close(); chrome.kill();
}
main().catch(e => { console.error(e); process.exit(1); });
