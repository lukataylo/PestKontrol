// Cloud Boost (opt-in): confirmed visits go to this server, which archives them
// on VAST and has NVIDIA verify, describe and embed them. Live video never leaves.
import { signal, effect } from '@preact/signals';
import { load, save } from './theme.js';

export const cloud = signal({ enabled: false, key: '', device: defaultDevice(), verifyFirst: false, ...load('shoo.cloud', {}) });
export const cloudStatus = signal(null);
effect(() => save('shoo.cloud', cloud.value));

function defaultDevice() {
  const ua = navigator.userAgent;
  const kind = /iPhone/.test(ua) ? 'iphone' : /iPad/.test(ua) ? 'ipad' : /Android/.test(ua) ? 'android' : 'camera';
  return `${kind}-${Math.random().toString(36).slice(2, 6)}`;
}

export const cloudOn = () => cloud.value.enabled && !!cloud.value.key;

async function api(path, body, { timeout = 20_000 } = {}) {
  const r = await fetch(path, {
    method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${cloud.value.key}` },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(timeout),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || `HTTP ${r.status}`);
  return j;
}

export async function refreshStatus() {
  try {
    cloudStatus.value = await api('/api/cloud/status');
  } catch (e) {
    cloudStatus.value = { error: e.message };
  }
  return cloudStatus.value;
}

const toBase64 = (blob) =>
  new Promise((res, rej) => {
    const r = new FileReader();
    r.onload = () => res(String(r.result).split(',')[1]);
    r.onerror = rej;
    r.readAsDataURL(blob);
  });

/// Sends a confirmed visit. Resolves with NVIDIA's verdict + where VAST stored it.
export async function sendEvent({ snapshot, species, confidence, at, outcome, pattern }, timeout = 25_000) {
  if (!cloudOn() || !snapshot) return null;
  return api('/api/events', {
    jpeg: await toBase64(snapshot), species, confidence, at: at.toISOString(), outcome, pattern, device: cloud.value.device,
  }, { timeout });
}

export const searchArchive = (query) => api('/api/search', { query, limit: 12 });
export const askArchive = (question, deviceLog) => api('/api/ask', { question, deviceLog }, { timeout: 45_000 });
export const imageURL = (key) => `/api/image?key=${encodeURIComponent(key)}`;
