// MobileCLIP-S0 in a worker: zero-shot pest classification and embeddings for
// plain-language search. Model and runtime are served by our own origin.
import {
  env, AutoTokenizer, AutoProcessor, CLIPTextModelWithProjection, CLIPVisionModelWithProjection, RawImage,
} from '@huggingface/transformers';

env.allowRemoteModels = false;
env.allowLocalModels = true;
env.localModelPath = '/models/';
env.useBrowserCache = true;
env.backends.onnx.wasm.wasmPaths = '/ort/';

const ID = 'Xenova/mobileclip_s0';

// Prompt ensembles, tuned on real photos: background prompts stop stone ledges
// and rooftops reading as "pigeon".
export const CLASSES = {
  pigeon: ['a photo of a pigeon', 'a pigeon standing on a ledge', 'a grey city pigeon'],
  gull: ['a photo of a seagull', 'a white and grey gull'],
  fox: ['a photo of a fox', 'a red fox'],
  rat: ['a photo of a rat', 'a brown rat', 'a rat with a long tail'],
  squirrel: ['a photo of a squirrel', 'a grey squirrel'],
  person: ['a photo of a person', 'a person standing'],
  cat: ['a photo of a cat'],
  dog: ['a photo of a dog'],
  hedgehog: ['a photo of a hedgehog', 'a spiky hedgehog'],
};
const BACKGROUND = [
  'an empty garden', 'a building wall', 'an empty balcony', 'a street', 'a rooftop', 'a room', 'a plain grey background',
  'a fence', 'trees', 'chimneys on a roof', 'an old stone building', 'a window ledge', 'a metal balcony railing',
  'sky and clouds', 'roof tiles', 'a brick wall', 'a doorway', 'a window', 'a lawn', 'a car park',
];

let tok, textModel, proc, vision, classEmbeds, classKeys;
const canvas = new OffscreenCanvas(256, 256);
const g2d = canvas.getContext('2d', { willReadFrequently: true });

const normalize = (v) => {
  let n = 0;
  for (let i = 0; i < v.length; i++) n += v[i] * v[i];
  n = Math.sqrt(n) || 1;
  const out = new Float32Array(v.length);
  for (let i = 0; i < v.length; i++) out[i] = v[i] / n;
  return out;
};
const dot = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i] * b[i]; return s; };

async function embedTexts(texts) {
  const inputs = tok(texts, { padding: 'max_length', max_length: 77, truncation: true });
  const { text_embeds } = await textModel(inputs);
  const d = text_embeds.dims[1];
  return texts.map((_, i) => normalize(text_embeds.data.slice(i * d, (i + 1) * d)));
}

async function init() {
  const progress = (p) => {
    if (p.status === 'progress') postMessage({ type: 'progress', file: p.file, loaded: p.loaded, total: p.total });
  };
  let gpu = false;
  try {
    gpu = !!(self.navigator?.gpu && (await navigator.gpu.requestAdapter()));
  } catch { /* no WebGPU */ }
  tok = await AutoTokenizer.from_pretrained(ID);
  textModel = await CLIPTextModelWithProjection.from_pretrained(ID, { dtype: 'q8', device: 'wasm', progress_callback: progress });
  proc = await AutoProcessor.from_pretrained(ID);
  // The int8 vision model is broken (random labels); fp16 on GPU, fp32 on CPU.
  try {
    vision = await CLIPVisionModelWithProjection.from_pretrained(ID, {
      dtype: gpu ? 'fp16' : 'fp32', device: gpu ? 'webgpu' : 'wasm', progress_callback: progress,
    });
  } catch (e) {
    if (!gpu) throw e;
    gpu = false;
    vision = await CLIPVisionModelWithProjection.from_pretrained(ID, { dtype: 'fp32', device: 'wasm', progress_callback: progress });
  }

  const keys = [], prompts = [];
  for (const [k, ps] of Object.entries(CLASSES)) for (const p of ps) { keys.push(k); prompts.push(p); }
  BACKGROUND.forEach((b, i) => { keys.push('bg' + i); prompts.push('a photo of ' + b); });
  const embeds = await embedTexts(prompts);
  classKeys = [...new Set(keys)];
  classEmbeds = classKeys.map((k) => {
    const sum = new Float32Array(embeds[0].length);
    keys.forEach((kk, i) => { if (kk === k) embeds[i].forEach((v, j) => (sum[j] += v)); });
    return normalize(sum);
  });
  postMessage({ type: 'ready', device: gpu ? 'webgpu' : 'wasm' });
}

function classify(emb) {
  const logits = classEmbeds.map((t) => 100 * dot(t, emb));
  const m = Math.max(...logits);
  const ex = logits.map((l) => Math.exp(l - m));
  const z = ex.reduce((a, b) => a + b, 0);
  const probs = {};
  classKeys.forEach((k, i) => { if (!k.startsWith('bg')) probs[k] = ex[i] / z; });
  return probs;
}

async function classifyRegions(bitmap, regions) {
  const images = regions.map((r) => {
    const sx = r.x * bitmap.width, sy = r.y * bitmap.height, sw = r.w * bitmap.width, sh = r.h * bitmap.height;
    const scale = 256 / Math.min(sw, sh);
    const tw = Math.max(1, Math.round(sw * scale)), th = Math.max(1, Math.round(sh * scale));
    canvas.width = tw;
    canvas.height = th;
    g2d.drawImage(bitmap, sx, sy, sw, sh, 0, 0, tw, th);
    const { data } = g2d.getImageData(0, 0, tw, th);
    return new RawImage(data, tw, th, 4).rgb();
  });
  bitmap.close();
  const inputs = await proc(images);
  const { image_embeds } = await vision(inputs);
  const d = image_embeds.dims[1];
  const data = image_embeds.data instanceof Float32Array ? image_embeds.data : Float32Array.from(image_embeds.data);
  return regions.map((r, i) => {
    const emb = normalize(data.slice(i * d, (i + 1) * d));
    return { id: r.id, probs: classify(emb), emb };
  });
}

let ready;
self.onmessage = async ({ data }) => {
  try {
    if (data.type === 'init') {
      ready ??= init();
      await ready;
    } else if (data.type === 'classify') {
      await ready;
      const results = await classifyRegions(data.bitmap, data.regions);
      postMessage({ type: 'result', id: data.id, results }, results.map((r) => r.emb.buffer));
    } else if (data.type === 'text') {
      await ready;
      const [emb] = await embedTexts([data.text]);
      postMessage({ type: 'text', id: data.id, emb }, [emb.buffer]);
    }
  } catch (e) {
    postMessage({ type: 'error', id: data.id, message: String(e?.message ?? e) });
  }
};
