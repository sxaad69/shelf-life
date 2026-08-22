#!/usr/bin/env node
/* SHELF LIFE — jsfxr SFX generator (6 files).
 * Mirrors scripts/game_audio.gd recipes; renders 16-bit WAV 22050 Hz mono,
 * then ffmpeg -> OGG 22kHz mono into assets/audio/.
 * All sounds generated-original (procedural), zero license risk.
 */
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const OUT_DIR = path.join(__dirname, "..", "assets", "audio");
fs.mkdirSync(OUT_DIR, { recursive: true });
const RATE = 22050;

function env(i, n, attack = 0.005) {
  const t = i / n;
  const a = Math.min(i / Math.max(attack * n, 1), 1);
  return a * Math.pow(1 - t, 2);
}

function render(name, dur, fn) {
  const n = Math.round(RATE * dur);
  const bytes = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) {
    let v = fn(i / RATE, i, n);
    v = Math.max(-1, Math.min(1, v));
    bytes.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  // WAV header
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + bytes.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(bytes.length, 40);
  const wavPath = path.join(OUT_DIR, name + ".wav");
  fs.writeFileSync(wavPath, Buffer.concat([header, bytes]));
  execSync(`ffmpeg -y -loglevel error -i ${wavPath} -acodec libvorbis -ar 22050 -ac 1 ${path.join(OUT_DIR, name + ".ogg")}`);
  fs.unlinkSync(wavPath);
  console.log("rendered", name + ".ogg");
}

// place-thock: decaying sine burst + click transient
render("place_thock", 0.12, (t, i, n) => {
  const f = 190 + 120 * Math.exp(-t * 60);
  let v = 0.6 * Math.sin(2 * Math.PI * f * t) + 0.25 * Math.sin(2 * Math.PI * f * 2.7 * t);
  if (i < 40) v += ((1 - i / 40) * 0.5 * (Math.random() * 2 - 1));
  return v * env(i, n, 0.001);
});

// badge-chime: rising two-note triangle
render("badge_chime", 0.35, (t, i, n) => {
  const note = t < 0.12 ? 659 : 988;
  const lt = t < 0.12 ? t : t - 0.12;
  const v = 0.4 * Math.sin(2 * Math.PI * note * t) + 0.15 * Math.sin(2 * Math.PI * note * 2 * t);
  return v * Math.min(lt / 0.004, 1) * Math.exp(-lt * 9);
});

// spoil-buzz: low square wobble (violation)
render("spoil_buzz", 0.3, (t, i, n) => {
  const f = 150 + 20 * Math.sin(2 * Math.PI * 9 * t);
  const sq = Math.sin(2 * Math.PI * f * t) > 0 ? 1 : -1;
  return 0.22 * sq * env(i, n, 0.01);
});

// open-shop bell: struck bell partials
render("shop_bell", 0.9, (t, i, n) => {
  const v = 0.5 * Math.sin(2 * Math.PI * 880 * t) + 0.3 * Math.sin(2 * Math.PI * 1320 * t)
    + 0.18 * Math.sin(2 * Math.PI * 2093 * t) * Math.exp(-t * 6);
  return v * Math.min(t / 0.002, 1) * Math.exp(-t * 3.5);
});

// hint-ping
render("hint_ping", 0.18, (t, i, n) => 0.35 * Math.sin(2 * Math.PI * 1245 * t) * env(i, n, 0.003));

// mellow shop loop ~8s A-minor-add9 pad, seamless (crossfaded tail)
{
  const dur = 8.0;
  const n = Math.round(RATE * dur);
  const freqs = [220.0, 261.63, 329.63, 493.88];
  const s = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    let v = 0;
    for (let fi = 0; fi < freqs.length; fi++) {
      const f = freqs[fi];
      const wob = 0.5 + 0.5 * Math.sin(2 * Math.PI * (0.11 + fi * 0.03) * t);
      v += 0.05 * Math.sin(2 * Math.PI * f * t + fi) * wob;
      v += 0.02 * Math.sin(2 * Math.PI * f * 2 * t) * wob;
    }
    s[i] = v;
  }
  const xf = Math.round(RATE * 0.5);
  for (let i = 0; i < xf; i++) {
    const blend = i / xf;
    s[i] = s[i] * blend + s[n - xf + i] * (1 - blend);
  }
  // write loop WAV directly (bypasses render()'s envelope machinery)
  const m = n - xf;
  const bytes = Buffer.alloc(m * 2);
  for (let i = 0; i < m; i++) {
    bytes.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s[i])) * 32767), i * 2);
  }
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + bytes.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(bytes.length, 40);
  const wavPath = path.join(OUT_DIR, "shop_loop.wav");
  fs.writeFileSync(wavPath, Buffer.concat([header, bytes]));
  execSync(`ffmpeg -y -loglevel error -i ${wavPath} -acodec libvorbis -ar 22050 -ac 1 ${path.join(OUT_DIR, "shop_loop.ogg")}`);
  fs.unlinkSync(wavPath);
  console.log("rendered shop_loop.ogg");
}
