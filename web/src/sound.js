// Every deterrent is synthesised on the fly and randomised, so animals don't
// learn a fixed pattern. Ported from the iOS Synth.

const RATE = 48000;
export const VOICES = ['hawk', 'clap', 'sweep', 'pulse'];
export const PATTERNS = [...VOICES, 'mix'];

let ctx;
let current;

/// Must be called from a tap — browsers only allow audio after a gesture.
export function unlockAudio() {
  ctx ??= new (window.AudioContext || window.webkitAudioContext)({ sampleRate: RATE });
  if (ctx.state === 'suspended') ctx.resume();
}

const rand = (a, b) => a + Math.random() * (b - a);
const randInt = (a, b) => Math.floor(rand(a, b + 1));

function hawk(out) {
  for (let c = randInt(2, 4); c > 0; c--) {
    const dur = rand(0.45, 0.8), n = Math.floor(dur * RATE);
    const f0 = rand(2600, 3400), drop = rand(700, 1300), vib = rand(22, 34);
    let ph = 0;
    for (let i = 0; i < n; i++) {
      const t = i / RATE;
      ph += (2 * Math.PI * (f0 - drop * (t / dur) + 140 * Math.sin(2 * Math.PI * vib * t))) / RATE;
      const env = Math.min(1, t / 0.02) * (1 - t / dur) ** 1.5;
      out.push((Math.sin(ph) + 0.35 * Math.sin(2 * ph) + 0.15 * Math.sin(3 * ph) + 0.12 * rand(-1, 1)) * env);
    }
    silence(out, rand(0.12, 0.35));
  }
}

function clap(out) {
  for (let c = randInt(8, 16); c > 0; c--) {
    const n = Math.floor(0.05 * RATE), tau = rand(0.006, 0.012);
    for (let i = 0; i < n; i++) out.push(rand(-1, 1) * Math.exp(-i / RATE / tau));
    silence(out, rand(0.05, 0.3));
  }
}

function sweep(out) {
  for (let c = randInt(12, 24); c > 0; c--) {
    const n = Math.floor(rand(0.04, 0.12) * RATE);
    const lo = rand(15000, 16500), hi = rand(18500, 19800), up = Math.random() < 0.5;
    let ph = 0;
    for (let i = 0; i < n; i++) {
      const x = i / n;
      ph += (2 * Math.PI * (up ? lo + (hi - lo) * x : hi - (hi - lo) * x)) / RATE;
      out.push(Math.sin(ph) * Math.sin(Math.PI * x));
    }
    silence(out, rand(0.02, 0.12));
  }
}

function pulse(out) {
  for (let k = randInt(10, 18); k > 0; k--) {
    const f = (k % 2 ? 17500 : 19000) + rand(-300, 300);
    const n = Math.floor(rand(0.06, 0.1) * RATE), ramp = 0.003 * RATE;
    for (let i = 0; i < n; i++) out.push(Math.sin((2 * Math.PI * f * i) / RATE) * Math.min(1, i / ramp, (n - i) / ramp));
    silence(out, rand(0.04, 0.09));
  }
}

function silence(out, s) {
  for (let i = Math.floor(s * RATE); i > 0; i--) out.push(0);
}

/// Plays a pattern and returns the voice actually used (resolves "mix").
export function play(pattern, gain = 0.9) {
  unlockAudio();
  const voice = pattern === 'mix' ? VOICES[randInt(0, 3)] : pattern;
  const out = [];
  ({ hawk, clap, sweep, pulse })[voice](out);
  const peak = out.reduce((m, v) => Math.max(m, Math.abs(v)), 0) || 1;
  const buf = ctx.createBuffer(1, out.length, RATE);
  const ch = buf.getChannelData(0);
  for (let i = 0; i < out.length; i++) ch[i] = (out[i] / peak) * 0.95;
  current?.stop();
  const src = ctx.createBufferSource();
  const g = ctx.createGain();
  g.gain.value = gain;
  src.buffer = buf;
  src.connect(g).connect(ctx.destination);
  src.start();
  current = src;
  return voice;
}
