// Main-thread side of detection: motion, region scheduling, novelty gating,
// tile memory, thumbnails. The model itself runs in detector.worker.js.
import { signal } from '@preact/signals';
import { load, save } from './theme.js';

export const PESTS = ['pigeon', 'gull', 'fox', 'rat', 'squirrel'];
export const FRIENDS = ['person', 'cat', 'dog', 'hedgehog'];
export const DARK_LUMA = 0.08;

/// phase: idle | loading | ready | error. `engine` is the user's choice: auto | gpu | cpu.
export const model = signal({ phase: 'idle', progress: 0, device: null, error: null, engine: load('shoo.engine', 'auto') });

let worker = null;
const pending = new Map();
let nextId = 1;
let files = {};

function makeWorker() {
  worker?.terminate();
  for (const p of pending.values()) p.reject(new Error('engine restarted'));
  pending.clear();
  files = {};
  worker = new Worker(new URL('./detector.worker.js', import.meta.url), { type: 'module' });
  worker.onerror = (e) => fail(`worker crashed: ${e.message || 'unknown error'}`);
  worker.onmessage = ({ data }) => {
    if (data.type === 'progress') {
      files[data.file] = [data.loaded, data.total];
      const [l, t] = Object.values(files).reduce(([a, b], [x, y]) => [a + x, b + y], [0, 0]);
      model.value = { ...model.value, phase: 'loading', progress: t ? l / t : 0 };
    } else if (data.type === 'attempt') {
      model.value = { ...model.value, trying: data.device === 'webgpu' ? 'GPU' : `CPU×${data.threads}` };
    } else if (data.type === 'ready') {
      model.value = { ...model.value, phase: 'ready', progress: 1, device: data.device, error: null };
    }
    const p = pending.get(data.id);
    if (p) {
      pending.delete(data.id);
      data.type === 'error' ? p.reject(new Error(data.message)) : p.resolve(data);
    }
  };
}

function fail(message) {
  model.value = { ...model.value, phase: 'error', error: message };
}

function call(msg, transfer = []) {
  if (!worker) makeWorker();
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    worker.postMessage({ ...msg, id }, transfer);
  });
}

/// Downloads (first time) and starts the on-device model. On failure, retries once
/// in a fresh worker on the safest engine — single-threaded CPU.
export async function loadModel({ force = false } = {}) {
  const m = model.value;
  if (!force && m.phase !== 'idle') return;
  model.value = { ...m, phase: 'loading', progress: 0, error: null };
  makeWorker();
  const errors = [];
  const ladders = m.engine === 'cpu' ? [{ engine: 'cpu', threads: 1 }] : [{ engine: m.engine }, { engine: 'cpu', threads: 1 }];
  for (const options of ladders) {
    try {
      await call({ type: 'init', options });
      return;
    } catch (e) {
      errors.push(e.message);
      makeWorker();
    }
  }
  fail(errors.join(' | '));
}

/// The "Install AI engine" / retry button. `clearCache` re-downloads the model files.
export async function installModel({ engine, clearCache = false } = {}) {
  if (engine) {
    save('shoo.engine', engine);
    model.value = { ...model.value, engine };
  }
  if (clearCache) {
    try {
      for (const k of await caches.keys()) if (/transformers/.test(k)) await caches.delete(k);
    } catch { /* no Cache API */ }
  }
  return loadModel({ force: true });
}

/// Text → embedding, for plain-language search.
export async function embedText(text) {
  return (await call({ type: 'text', text })).emb;
}

export const cosine = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i] * b[i]; return s; };

const FULL = { id: 'full', x: 0, y: 0, w: 1, h: 1 };
const TILES = [0, 1, 2, 3].map((i) => ({ id: 't' + i, x: (i % 2) * 0.4, y: Math.floor(i / 2) * 0.4, w: 0.6, h: 0.6 }));

/// Watches a <video>, emits a frame result roughly every `interval` ms.
export class Detector {
  constructor(onFrame) {
    this.onFrame = onFrame;
    this.interval = 650;
    this.busy = false;
    this.tick = 0;
    this.baselines = {};
    this.tileMemory = {};
    this.motionBg = null;
    this.small = document.createElement('canvas');
    this.small.width = 36;
    this.small.height = 64;
    this.thumbCanvas = document.createElement('canvas');
    this.lastThumb = 0;
    this.timer = null;
  }

  start(video) {
    this.video = video;
    loadModel();
    clearInterval(this.timer);
    this.timer = setInterval(() => this.step(), 120);
  }

  stop() {
    clearInterval(this.timer);
  }

  /// Luma grid diff → moving box (normalized, top-left origin) + mean brightness.
  motion() {
    const v = this.video, c = this.small;
    const portrait = v.videoHeight >= v.videoWidth;
    c.width = portrait ? 36 : 64;
    c.height = portrait ? 64 : 36;
    const g = c.getContext('2d', { willReadFrequently: true });
    g.drawImage(v, 0, 0, c.width, c.height);
    const { data } = g.getImageData(0, 0, c.width, c.height);
    const cols = c.width / 4, rows = c.height / 4;
    const cells = new Float32Array(cols * rows);
    let sum = 0;
    for (let y = 0; y < c.height; y++) {
      for (let x = 0; x < c.width; x++) {
        const i = (y * c.width + x) * 4;
        const l = (0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]) / 255;
        cells[Math.floor(y / 4) * cols + Math.floor(x / 4)] += l / 16;
        sum += l;
      }
    }
    const luma = sum / (c.width * c.height);
    if (!this.motionBg || this.motionBg.length !== cells.length) {
      this.motionBg = cells;
      return { box: null, luma };
    }
    let minC = cols, maxC = -1, minR = rows, maxR = -1, n = 0;
    for (let i = 0; i < cells.length; i++) {
      if (Math.abs(cells[i] - this.motionBg[i]) > 0.07) {
        const r = Math.floor(i / cols), cc = i % cols;
        minC = Math.min(minC, cc); maxC = Math.max(maxC, cc); minR = Math.min(minR, r); maxR = Math.max(maxR, r);
        n++;
      }
      this.motionBg[i] = this.motionBg[i] * 0.9 + cells[i] * 0.1;
    }
    if (n < 2 || n > cells.length / 2) return { box: null, luma };
    const w = (maxC - minC + 1) / cols, h = (maxR - minR + 1) / rows;
    const x = minC / cols, y = minR / rows;
    const pad = (a, b, s) => [Math.max(0, a - s * 0.4), Math.min(1, b + s * 0.4)];
    const [x0, x1] = pad(x, x + w, w), [y0, y1] = pad(y, y + h, h);
    // Make it squarer so the model sees context, not a sliver.
    return { box: { id: 'motion', x: x0, y: y0, w: x1 - x0, h: y1 - y0 }, luma };
  }

  async step() {
    const v = this.video;
    if (this.busy || !v || v.readyState < 2 || v.videoWidth === 0) return;
    if (model.value.phase !== 'ready') {
      if (model.value.phase === 'error') this.basic();
      return;
    }
    if (performance.now() - (this.lastRun ?? 0) < this.interval) return;
    this.busy = true;
    this.lastRun = performance.now();
    try {
      const { box: moving, luma } = this.motion();
      const tiles = [TILES[(this.tick * 2) % 4], TILES[(this.tick * 2 + 1) % 4]];
      this.tick++;
      const regions = [FULL, ...tiles, ...(moving ? [moving] : [])];
      const bitmap = await createImageBitmap(v);
      const { results } = await call({ type: 'classify', bitmap, regions }, [bitmap]);
      this.onFrame(await this.combine(results, regions, moving, luma));
    } catch (e) {
      console.warn('detect', e);
    } finally {
      this.busy = false;
    }
  }

  /// Basic mode when the AI can't run here: movement, brightness and thumbnails only.
  async basic() {
    if (performance.now() - (this.lastRun ?? 0) < this.interval) return;
    this.busy = true;
    this.lastRun = performance.now();
    try {
      const { box, luma } = this.motion();
      const frame = { species: null, confidence: 0, guarded: null, guardedConfidence: 0, box, moving: !!box, luma, labels: {}, at: new Date() };
      const now = performance.now();
      if (now - this.lastThumb >= (box ? 1000 : 10000)) {
        this.lastThumb = now;
        frame.thumb = await this.grab(320, 0.55);
      }
      if (box) frame.snapshot = frame.thumb ?? (await this.grab(320, 0.55));
      this.onFrame(frame);
    } finally {
      this.busy = false;
    }
  }

  /// A region only counts as a pest if it changed from what it usually looks
  /// like — stops ledges that always look a bit "pigeon" from firing forever.
  novelty(id, emb, pestScore) {
    const base = this.baselines[id];
    if (!base) {
      this.baselines[id] = emb;
      return 0;
    }
    const change = 1 - cosine(base, emb);
    if (pestScore < 0.3) {
      const mixed = base.map((b, i) => b * 0.92 + emb[i] * 0.08);
      const n = Math.hypot(...mixed) || 1;
      this.baselines[id] = mixed.map((x) => x / n);
    }
    return Math.max(0, Math.min(1, (change - 0.015) / 0.05));
  }

  async combine(results, regions, moving, luma) {
    const now = performance.now();
    const hits = [];
    for (const r of results) {
      const region = regions.find((x) => x.id === r.id);
      const pest = PESTS.reduce((a, b) => (r.probs[a] > r.probs[b] ? a : b));
      const gate = r.id === 'motion' ? 1 : this.novelty(r.id, r.emb, r.probs[pest]);
      const hit = { ...r, region, gate, at: now };
      if (r.id.startsWith('t')) this.tileMemory[r.id] = hit;
      else hits.push(hit);
    }
    for (const m of Object.values(this.tileMemory)) if (now - m.at < 2000 && !hits.includes(m)) hits.push(m);

    const frame = {
      species: null, confidence: 0, guarded: null, guardedConfidence: 0, box: null,
      moving: !!moving, luma, labels: {}, embedding: results.find((r) => r.id === 'full')?.emb, at: new Date(),
    };
    for (const h of hits) {
      for (const [k, p] of Object.entries(h.probs)) frame.labels[k] = Math.max(frame.labels[k] ?? 0, p);
      for (const k of PESTS) {
        const s = h.probs[k] * h.gate;
        if (s > frame.confidence) { frame.species = k; frame.confidence = s; frame.box = h.region; }
      }
      for (const k of FRIENDS) {
        if (h.probs[k] > frame.guardedConfidence) { frame.guarded = k; frame.guardedConfidence = h.probs[k]; }
      }
    }
    if (frame.box && moving && frame.box.id !== 'motion' && overlaps(moving, frame.box)) frame.box = moving;

    const busy = frame.moving || frame.confidence >= 0.3 || frame.guardedConfidence >= 0.5;
    if (now - this.lastThumb >= (busy ? 1000 : 10000)) {
      this.lastThumb = now;
      frame.thumb = await this.grab(320, 0.55);
    }
    if (frame.confidence >= 0.35) frame.snapshot = frame.thumb ?? (await this.grab(320, 0.55));
    return frame;
  }

  grab(width, quality) {
    const v = this.video, c = this.thumbCanvas;
    c.width = width;
    c.height = Math.round((width * v.videoHeight) / v.videoWidth);
    c.getContext('2d').drawImage(v, 0, 0, c.width, c.height);
    return new Promise((res) => c.toBlob(res, 'image/jpeg', quality));
  }
}

const overlaps = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
