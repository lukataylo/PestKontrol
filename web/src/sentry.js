// The brain, ported from the iOS Sentry: confirms detections over frames,
// respects safety + cooldown + quiet hours, deters, logs, indexes, runs rules.
import { signal, computed, effect } from '@preact/signals';
import { Detector, DARK_LUMA, PESTS } from './detector.js';
import { Recorder } from './recorder.js';
import { add, pruneBefore, persist } from './store.js';
import { play, unlockAudio } from './sound.js';
import { ruleActive } from './recall.js';
import { load, save } from './theme.js';

export const MODES = {
  gentle: { label: 'GENTLE', blurb: 'Waits until sure. Softer, rarer.', level: 1, tuning: { threshold: 0.6, confirm: 3, cooldown: 120, gain: 0.7 } },
  steady: { label: 'NORMAL', blurb: 'Balanced. The good default.', level: 2, tuning: { threshold: 0.45, confirm: 2, cooldown: 45, gain: 0.9 } },
  fierce: { label: 'FIERCE', blurb: 'Acts fast. Loud and often.', level: 3, tuning: { threshold: 0.3, confirm: 2, cooldown: 20, gain: 1 } },
};

export const DEFAULT_PATTERN = { pigeon: 'hawk', gull: 'hawk', fox: 'clap', rat: 'sweep', squirrel: 'pulse' };

const defaults = {
  enabled: [...PESTS], patterns: {}, mode: 'steady', custom: MODES.steady.tuning,
  protectLock: true, quietHours: false, quietStart: 22, quietEnd: 7,
};

export const settings = signal({ ...defaults, ...load('shoo.settings', {}) });
export const recall = signal({ record: true, keepHours: 6, ...load('shoo.recall', {}) });
export const rules = signal(load('shoo.rules', []));
export const onboarded = signal(load('shoo.onboarded', false));
effect(() => save('shoo.settings', settings.value));
effect(() => save('shoo.recall', recall.value));
effect(() => save('shoo.rules', rules.value));
effect(() => save('shoo.onboarded', onboarded.value));

export const tuning = computed(() => MODES[settings.value.mode]?.tuning ?? settings.value.custom);
export const patternFor = (sp) => settings.value.patterns[sp] ?? DEFAULT_PATTERN[sp];

export const armed = signal(false);
export const torch = signal(false);
export const stealth = signal(false);
export const running = signal(false);
export const cameraError = signal(null);
export const frame = signal(null);
export const status = signal({ kind: 'offline' });
export const firings = signal([]);
export const stream = signal(null);
export const torchSupported = signal(false);

export function isQuiet(date = new Date()) {
  const s = settings.value;
  if (!s.quietHours) return false;
  const h = date.getHours();
  return s.quietStart <= s.quietEnd ? h >= s.quietStart && h < s.quietEnd : h >= s.quietStart || h < s.quietEnd;
}

export const recorder = new Recorder();
effect(() => {
  recorder.keepHours = recall.value.keepHours;
  recorder.setEnabled(recall.value.record);
});

const detector = new Detector(ingest);
const hidden = document.createElement('video');
hidden.muted = true;
hidden.playsInline = true;
hidden.setAttribute('playsinline', '');

let streak = 0, streakSpecies = null, cooldownUntil = 0, holdUntil = 0;
let lastMoment = 0, lastPrune = 0;
const ruleLast = {};
let wakeLock = null;

export async function start() {
  if (running.value) return;
  try {
    const s = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 15, max: 30 } },
      audio: false,
    });
    stream.value = s;
    hidden.srcObject = s;
    await hidden.play();
    const track = s.getVideoTracks()[0];
    torchSupported.value = !!track.getCapabilities?.().torch;
    detector.start(hidden);
    recorder.start(s);
    running.value = true;
    cameraError.value = null;
    status.value = { kind: 'idle' };
    persist();
    keepAwake();
  } catch (e) {
    cameraError.value = e?.name === 'NotAllowedError' ? 'denied' : (e?.message ?? 'camera unavailable');
  }
}

async function keepAwake() {
  try {
    wakeLock = await navigator.wakeLock?.request('screen');
  } catch { /* not supported or not visible */ }
}
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && running.value) keepAwake();
});

export function setArmed(on) {
  if (on) unlockAudio();
  armed.value = on;
}

export async function setTorch(on) {
  const track = stream.value?.getVideoTracks()[0];
  if (!track || !torchSupported.value) return;
  try {
    await track.applyConstraints({ advanced: [{ torch: on }] });
    torch.value = on;
  } catch { /* torch refused */ }
}

export function test(pattern) {
  return play(pattern, tuning.value.gain);
}

function rest(now, f) {
  if (now < cooldownUntil) return { kind: 'cooldown', secs: Math.ceil((cooldownUntil - now) / 1000) };
  return f.luma < DARK_LUMA ? { kind: 'dark' } : { kind: 'idle' };
}

function ingest(f) {
  frame.value = f;
  const now = Date.now();
  const t = tuning.value;
  const s = settings.value;
  index(f, now);
  frameRules(f);

  // A clear person always wins; anything else only if it outranks the pest.
  if (s.protectLock && f.guarded &&
      ((f.guarded === 'person' && f.guardedConfidence >= 0.55) ||
       (f.guardedConfidence >= 0.35 && (!f.species || f.guardedConfidence >= f.confidence)))) {
    streak = 0;
    if (now >= holdUntil) status.value = { kind: 'held', who: f.guarded };
    return;
  }

  const sp = f.species;
  if (!sp || f.confidence < t.threshold || !s.enabled.includes(sp)) {
    streak = Math.max(0, streak - 1);
    if (now >= holdUntil) status.value = rest(now, f);
    return;
  }
  streak = sp === streakSpecies ? streak + 1 : 1;
  streakSpecies = sp;
  if (now < cooldownUntil) {
    if (now >= holdUntil) status.value = rest(now, f);
    return;
  }
  if (streak < t.confirm) {
    status.value = { kind: 'tracking', species: sp, n: streak, of: t.confirm };
    return;
  }

  streak = 0;
  cooldownUntil = now + t.cooldown * 1000;
  holdUntil = now + 3000;
  let outcome, pattern = null;
  if (!armed.value) {
    outcome = 'logged';
    status.value = { kind: 'logged', species: sp };
  } else if (isQuiet()) {
    outcome = 'quiet';
    status.value = { kind: 'quiet', species: sp };
  } else {
    pattern = play(patternFor(sp), t.gain);
    outcome = 'fired';
    status.value = { kind: 'firing', species: sp, pattern };
  }
  add('sightings', { at: f.at, species: sp, confidence: f.confidence, outcome, pattern, snapshot: f.snapshot ?? null, dark: f.luma < DARK_LUMA });
  runRules(sp.toUpperCase(), `${Math.round(f.confidence * 100)}%`, (tr) => tr.type === 'pest' && (!tr.species.length || tr.species.includes(sp)), sp, f.confidence);
}

/// The searchable timeline: every ~4 s when quiet, every ~1 s when busy.
function index(f, now) {
  const busy = f.moving || f.confidence >= 0.3 || f.guardedConfidence >= 0.5;
  if (now - lastMoment < (busy ? 1000 : 4000)) return;
  lastMoment = now;
  add('moments', {
    at: f.at, species: f.species, confidence: f.confidence, guarded: f.guarded, guardedConfidence: f.guardedConfidence,
    moving: f.moving, dark: f.luma < DARK_LUMA, labels: f.labels, emb: f.embedding ?? null, thumb: f.thumb ?? null,
  });
  if (now - lastPrune > 600_000) {
    lastPrune = now;
    const cutoff = new Date(now - Math.max(recall.value.keepHours, 48) * 3600_000);
    pruneBefore('moments', cutoff);
  }
}

function frameRules(f) {
  if (f.guarded === 'person' && f.guardedConfidence >= 0.55) {
    runRules('PERSON', `${Math.round(f.guardedConfidence * 100)}%`, (t) => t.type === 'person');
  } else if (f.guarded && f.guarded !== 'person' && f.guardedConfidence >= 0.55 && f.guardedConfidence >= f.confidence) {
    runRules(f.guarded.toUpperCase(), 'friend', (t) => t.type === 'friend');
  }
  if (f.moving) runRules('MOVEMENT', '', (t) => t.type === 'motion');
}

function runRules(subject, detail, matches, species = null, confidence = 0) {
  const now = Date.now();
  for (const r of rules.value) {
    if (!ruleActive(r) || !matches(r.trigger)) continue;
    if (now - (ruleLast[r.id] ?? 0) < r.cooldown * 1000) continue;
    ruleLast[r.id] = now;
    const did = [];
    for (const a of r.actions) {
      if (a === 'deter') did.push(play(species ? patternFor(species) : 'mix', tuning.value.gain).toUpperCase());
      if (a === 'lamp' && torchSupported.value) { strobe(); did.push('LAMP'); }
      if (a === 'notify') { notify(`SHOO · ${subject}`, detail ? `${detail} — ${r.text}` : r.text); did.push('NOTIFY'); }
      if (a === 'webhook' && r.webhook) {
        fetch(r.webhook, {
          method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ event: subject.toLowerCase(), detail, rule: r.text, confidence, time: new Date().toISOString() }),
        }).catch(() => {});
        did.push('WEBHOOK');
      }
    }
    firings.value = [{ at: new Date(), what: `${subject} → ${did.join(' · ') || 'nothing'}` }, ...firings.value].slice(0, 30);
  }
}

async function strobe() {
  const restore = torch.value;
  for (let i = 0; i < 8; i++) {
    await setTorch(i % 2 === 0);
    await new Promise((r) => setTimeout(r, 220));
  }
  await setTorch(restore);
}

export async function askNotifications() {
  try {
    if ('Notification' in window && Notification.permission === 'default') await Notification.requestPermission();
  } catch { /* unsupported */ }
}

async function notify(title, body) {
  try {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg) reg.showNotification(title, { body, icon: '/icons/icon-192.png', tag: 'shoo-' + Date.now() });
    else new Notification(title, { body });
  } catch { /* best effort */ }
}

// MARK: Bot voice

export function mood(st, isArmed, slasherTheme) {
  switch (st.kind) {
    case 'offline': return 'dead';
    case 'idle': return slasherTheme && isArmed ? 'happy' : 'idle';
    case 'dark': return 'sleepy';
    case 'tracking': return 'suspicious';
    case 'firing': return 'angry';
    case 'logged': case 'quiet': return 'surprised';
    case 'cooldown': return 'smug';
    case 'held': return 'happy';
    case 'loading': return 'sleepy';
  }
  return 'idle';
}

export function line(st, isArmed, slasherTheme) {
  const S = (x) => (x ?? '').toUpperCase();
  if (slasherTheme) {
    switch (st.kind) {
      case 'offline': return 'Camera off';
      case 'loading': return 'Waking up...';
      case 'idle': return isArmed ? 'All clear' : 'Camera ready';
      case 'dark': return 'Too dark. Lamp?';
      case 'tracking': return `Target: ${S(st.species)}?`;
      case 'firing': return 'Intruder detected';
      case 'logged': return `${S(st.species)} spotted`;
      case 'quiet': return `${S(st.species)}. Quiet hours.`;
      case 'cooldown': return "They'll be back";
      case 'held': return st.who === 'person' ? 'Human. Holding fire.' : `${S(st.who)}. Holding fire.`;
    }
  }
  switch (st.kind) {
    case 'offline': return 'Camera off.';
    case 'loading': return 'Waking up...';
    case 'idle': return isArmed ? 'All clear. Armed.' : 'All clear. Tap arm to scare.';
    case 'dark': return 'Too dark. Lamp?';
    case 'tracking': return `Hmm... ${S(st.species)}?`;
    case 'firing': return `Shoo, ${S(st.species)}!`;
    case 'logged': return `${S(st.species)}! Logged it.`;
    case 'quiet': return `${S(st.species)}. Shh, quiet hours.`;
    case 'cooldown': return "That told 'em.";
    case 'held': return st.who === 'person' ? 'Hi human. Staying quiet.' : `Hi ${S(st.who)}. No noise.`;
  }
  return '';
}
