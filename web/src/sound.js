// Every deterrent is synthesised on the fly and randomised, so animals don't
// learn a fixed pattern. Ported from the iOS Synth.

const RATE = 48000;
export const VOICES = ['hawk', 'bark', 'siren', 'shout', 'clap', 'sweep', 'pulse'];
export const PATTERNS = [...VOICES, 'mix'];

/// What each sound is, for the picker. High ones are real but most adults can't hear them.
export const SOUND_INFO = {
  hawk: { name: 'HAWK', text: 'Raptor screech. Birds fear it.' },
  bark: { name: 'BARK', text: 'Big dog barking. Works on foxes and cats.' },
  siren: { name: 'SIREN', text: 'Rising alarm. Loud and startling.' },
  shout: { name: 'SHOUT', text: 'Harsh human-like "hey!" bursts.' },
  clap: { name: 'CLAP', text: 'Sharp claps at random gaps.' },
  sweep: { name: 'SWEEP', text: 'High chirps, 15–20 kHz. You may not hear it.', high: true },
  pulse: { name: 'PULSE', text: 'High beeps, 17–19 kHz. You may not hear it.', high: true },
  mix: { name: 'MIX', text: 'A different audible sound each time.' },
};
const AUDIBLE = ['hawk', 'bark', 'siren', 'shout', 'clap'];

let ctx;
let current;

/// Must be called from a tap — browsers only allow audio after a gesture.
export function unlockAudio() {
  // iOS mutes Web Audio with the silent switch unless the session is "playback".
  try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch { /* older Safari */ }
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

/// Two or three deep barks: harmonic voice with a falling pitch plus breath noise.
function bark(out) {
  for (let c = randInt(2, 3); c > 0; c--) {
    const dur = rand(0.16, 0.24), n = Math.floor(dur * RATE);
    const f0 = rand(420, 560), f1 = f0 * rand(0.55, 0.7);
    let ph = 0;
    for (let i = 0; i < n; i++) {
      const t = i / RATE, x = t / dur;
      ph += (2 * Math.PI * (f0 + (f1 - f0) * x)) / RATE;
      const env = Math.min(1, t / 0.008) * (1 - x) ** 1.6;
      out.push((0.6 * Math.sin(ph) + 0.35 * Math.sin(2 * ph) + 0.25 * Math.sin(3 * ph) + 0.15 * Math.sin(5 * ph) + 0.35 * rand(-1, 1)) * env);
    }
    silence(out, rand(0.12, 0.28));
  }
}

/// Wailing alarm sweeping 700–1600 Hz.
function siren(out) {
  const dur = rand(1.8, 2.6), n = Math.floor(dur * RATE), rate = rand(1.2, 2.2);
  let ph = 0;
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    ph += (2 * Math.PI * (1150 + 450 * Math.sin(2 * Math.PI * rate * t))) / RATE;
    const env = Math.min(1, t / 0.05, (dur - t) / 0.08);
    out.push((Math.sin(ph) + 0.4 * Math.sin(2 * ph) + 0.2 * Math.sign(Math.sin(ph))) * env);
  }
}

/// Short harsh vowel bursts, roughly a shouted "hey!".
function shout(out) {
  for (let c = randInt(2, 3); c > 0; c--) {
    const dur = rand(0.28, 0.4), n = Math.floor(dur * RATE), f0 = rand(190, 260);
    let ph = 0;
    for (let i = 0; i < n; i++) {
      const t = i / RATE, x = t / dur;
      ph += (2 * Math.PI * f0 * (1 + 0.25 * x)) / RATE;
      // Buzzy source shaped by two rough formants (~700 Hz and ~1800 Hz).
      const src = Math.sin(ph) + 0.5 * Math.sin(2 * ph) + 0.33 * Math.sin(3 * ph);
      const formant = 0.6 * Math.sin(ph * (700 / f0)) + 0.35 * Math.sin(ph * (1800 / f0));
      const env = Math.min(1, t / 0.02) * (1 - x) ** 0.8;
      out.push((src * 0.5 + formant * 0.6 + 0.1 * rand(-1, 1)) * env);
    }
    silence(out, rand(0.15, 0.3));
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
  const voice = pattern === 'mix' ? AUDIBLE[randInt(0, AUDIBLE.length - 1)] : (VOICES.includes(pattern) ? pattern : 'hawk');
  const out = [];
  ({ hawk, bark, siren, shout, clap, sweep, pulse })[voice](out);
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
