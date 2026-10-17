// Search, ask, spot and rules over the moment index. Ported from the iOS
// RecallEngine, with MobileCLIP embeddings for real plain-language search.
import { range } from './store.js';
import { embedText, cosine, PESTS, FRIENDS } from './detector.js';
import { clock, stamp } from './theme.js';

const SYNONYMS = {
  bird: ['pigeon', 'gull'], birds: ['pigeon', 'gull'], pigeons: ['pigeon'], dove: ['pigeon'], seagull: ['gull'],
  seagulls: ['gull'], gulls: ['gull'], foxes: ['fox'], rats: ['rat'], mice: ['rat'], mouse: ['rat'], rodent: ['rat'],
  squirrels: ['squirrel'], people: ['person'], someone: ['person'], somebody: ['person'], anyone: ['person'],
  human: ['person'], man: ['person'], woman: ['person'], cats: ['cat'], dogs: ['dog'], hedgehogs: ['hedgehog'],
  pest: PESTS, pests: PESTS, animal: [...PESTS, 'cat', 'dog', 'hedgehog'], animals: [...PESTS, 'cat', 'dog', 'hedgehog'],
};
const KNOWN = new Set([...PESTS, ...FRIENDS]);
const MOTION = /\b(mov(e|ing|ement)|motion)\b/;
const ANYTHING = /\b(what happened|anything|activity|everything|busiest|summary|summarise|summarize)\b/;

// MARK: Time phrases

export function timeWindow(text, now = new Date(), horizonHours = 24) {
  const s = text.toLowerCase();
  const day = new Date(now); day.setHours(0, 0, 0, 0);
  const at = (d, h) => new Date(d.getTime() + h * 3600_000);
  const clamp = (a, b) => [a, b > now ? now : b];
  const num = (unit) => {
    const m = new RegExp(`(\\d+|a|an|one|two|three|four|five|six|ten|twelve)\\s+${unit}`).exec(s);
    if (!m) return null;
    const words = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, ten: 10, twelve: 12 };
    return Number(m[1]) || words[m[1]];
  };
  const h = num('hour'), m = num('minute');
  if (h) return [new Date(now - h * 3600_000), now];
  if (m) return [new Date(now - m * 60_000), now];
  if (/(last|past) hour/.test(s)) return [new Date(now - 3600_000), now];
  if (/last night|overnight|tonight/.test(s)) {
    const start = now.getHours() >= 20 ? at(day, 20) : at(day, -4);
    return clamp(start, at(start, 11));
  }
  if (/yesterday/.test(s)) return [at(day, -24), day];
  if (/this morning/.test(s)) return clamp(at(day, 5), at(day, 12));
  if (/this afternoon/.test(s)) return clamp(at(day, 12), at(day, 18));
  if (/this evening/.test(s)) return clamp(at(day, 18), at(day, 24));
  if (/today/.test(s)) return [day, now];
  return [new Date(now - horizonHours * 3600_000), now];
}

// MARK: Search

export function subjects(text) {
  const words = text.toLowerCase().match(/[a-z]+/g) ?? [];
  const out = new Set();
  for (const w of words) {
    if (KNOWN.has(w)) out.add(w);
    for (const s of SYNONYMS[w] ?? []) out.add(s);
  }
  return [...out];
}

/// Strips time words so "pigeons this morning" embeds as "pigeons".
function visualPart(text) {
  return text
    .toLowerCase()
    .replace(/\b(show me|find|search( for)?|every|all|any|when did|was there|were there|did|the|a|an)\b/g, ' ')
    .replace(/\b(last|past|this|today|yesterday|tonight|overnight|morning|afternoon|evening|night|hours?|minutes?|\d+|ago)\b/g, ' ')
    .replace(/[?!.]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function group(hits, gap = 15_000) {
  const clips = [];
  for (const [m, s] of hits.sort((a, b) => a[0].at - b[0].at)) {
    const last = clips.at(-1);
    if (last && m.at - last.end <= gap) {
      last.end = m.at;
      if (m.thumb && (s > last.score || !last.thumb)) last.thumb = m.thumb;
      last.score = Math.max(last.score, s);
    } else {
      clips.push({ kind: m.species && m.confidence >= 0.35 ? m.species : 'match', start: m.at, end: m.at, score: s, thumb: m.thumb });
    }
  }
  return clips;
}

/// Plain-language search: label matches plus MobileCLIP text↔frame similarity.
export async function search(text, { horizonHours = 24, limit = 24 } = {}) {
  const [from, to] = timeWindow(text, new Date(), horizonHours);
  const moments = await range('moments', from, to);
  const subs = subjects(text);
  const motionOnly = MOTION.test(text.toLowerCase());
  const visual = visualPart(text);
  let q = null;
  if (visual && !ANYTHING.test(text.toLowerCase())) {
    try { q = await embedText('a photo of ' + visual); } catch { /* model not ready: labels only */ }
  }
  const sims = q ? moments.map((m) => (m.emb ? cosine(q, m.emb) : 0)) : [];
  // CLIP similarities are relative: compare against this window's own spread.
  const sorted = [...sims].sort((a, b) => a - b);
  const p90 = sorted[Math.floor(sorted.length * 0.9)] ?? 1;
  const p50 = sorted[Math.floor(sorted.length * 0.5)] ?? 0;

  const hits = [];
  moments.forEach((m, i) => {
    if (motionOnly && !m.moving) return;
    let s = 0;
    for (const k of subs) s = Math.max(s, m.labels?.[k] ?? 0);
    if (q && m.emb) {
      const rel = (sims[i] - p50) / Math.max(0.01, p90 - p50);
      if (sims[i] > 0.22 && rel > 1) s = Math.max(s, Math.min(1, 0.4 + (rel - 1) * 0.3));
    }
    if (!subs.length && !q) s = Math.max(m.confidence ?? 0, m.guardedConfidence * 0.8, m.moving ? 0.3 : 0);
    if (s >= 0.3) hits.push([m, s]);
  });
  const clips = group(hits).sort((a, b) => b.score - a.score).slice(0, limit).sort((a, b) => b.start - a.start);
  return { clips, window: [from, to] };
}

// MARK: Spot

export async function spot(from, to, threshold = 0.45) {
  const moments = await range('moments', from, to);
  const clips = [];
  const runs = (kind, test) => {
    let cur = null;
    for (const m of moments) {
      const s = test(m);
      if (s == null) continue;
      if (cur && m.at - cur.end <= 20_000) {
        cur.end = m.at;
        if (m.thumb && s >= cur.score) cur.thumb = m.thumb;
        cur.score = Math.max(cur.score, s);
      } else {
        if (cur) clips.push(cur);
        cur = { kind, start: m.at, end: m.at, score: s, thumb: m.thumb };
      }
    }
    if (cur) clips.push(cur);
  };
  for (const p of PESTS) runs(p, (m) => (m.species === p && m.confidence >= threshold ? m.confidence : null));
  for (const f of FRIENDS) runs(f, (m) => (m.guarded === f && m.guardedConfidence >= 0.55 ? m.guardedConfidence : null));
  runs('movement', (m) => (m.moving && (m.confidence ?? 0) < threshold && m.guardedConfidence < 0.55 ? 0.3 : null));
  const real = clips.filter((c) => c.kind !== 'movement' || c.end - c.start >= 2000);

  let dark = null, since = 0;
  for (const m of moments) {
    if (dark === null) { dark = m.dark; since = m.at; continue; }
    if (m.dark !== dark && m.at - since > 30_000) {
      real.push({ kind: m.dark ? 'lights down' : 'lights up', start: m.at, end: m.at, score: 0.2, thumb: m.thumb });
      dark = m.dark;
      since = m.at;
    }
  }
  return real.sort((a, b) => b.start - a.start);
}

export const range2 = (c) => (clock(c.start) === clock(c.end) ? clock(c.start) : `${clock(c.start)}–${clock(c.end)}`);

// MARK: Ask

export async function ask(question, { horizonHours = 24, threshold = 0.45, sightings = [] } = {}) {
  const [from, to] = timeWindow(question, new Date(), horizonHours);
  const events = await spot(from, to, threshold);
  const subs = subjects(question);
  const relevant = subs.length ? events.filter((e) => subs.includes(e.kind)) : events;
  const scared = sightings.filter((s) => s.at >= from && s.at <= to && s.outcome === 'fired');

  const log = [`Window: ${stamp(from)} to ${stamp(to)}`]
    .concat(events.slice().reverse().slice(-40).map((e) => `${range2(e)} ${e.kind}${e.score > 0.3 && PESTS.includes(e.kind) ? ` (${Math.round(e.score * 100)}%)` : ''}`))
    .concat(scared.slice(-20).map((s) => `${clock(s.at)} scared off ${s.species} with ${s.pattern}`));
  if (log.length === 1) log.push('Nothing detected.');

  const ai = await browserAI(question, log.join('\n'));
  const text = ai ?? summary(relevant.length || !subs.length ? relevant : [], scared, from, to, subs);
  return { text, clips: relevant.slice(0, 8), usedAI: !!ai, window: [from, to], log: log.join('\n') };
}

function summary(events, scared, from, to, subs) {
  const real = events.filter((e) => !e.kind.startsWith('lights'));
  if (!real.length) return `Nothing${subs.length ? ` like ${subs.join(' or ')}` : ''} seen between ${clock(from)} and ${clock(to)}.`;
  const by = {};
  for (const e of real) (by[e.kind] ??= []).push(e);
  const parts = Object.entries(by)
    .sort((a, b) => b[1].length - a[1].length)
    .slice(0, 4)
    .map(([k, es]) => `${k} ×${es.length} (${es.slice().reverse().slice(0, 3).map((e) => clock(e.start)).join(', ')})`);
  return `Saw ${parts.join('; ')}.${scared.length ? ` Scared off ${scared.length}.` : ''}`;
}

/// Chrome's built-in on-device model, when the browser has one. Never a server.
async function browserAI(question, log) {
  try {
    const LM = globalThis.LanguageModel;
    if (!LM || (await LM.availability()) !== 'available') return null;
    const session = await LM.create({
      initialPrompts: [{
        role: 'system',
        content: 'You are SHOO, a phone on a windowsill watching for pests. Answer using only the activity log. ' +
          'Two or three short sentences. Mention times. If nothing relevant, say you saw nothing.',
      }],
    });
    const out = await session.prompt(`Activity log:\n${log}\n\nQuestion: ${question}`);
    session.destroy?.();
    return out.trim();
  } catch {
    return null;
  }
}

export const aiStatus = async () => {
  try {
    return globalThis.LanguageModel && (await globalThis.LanguageModel.availability()) === 'available';
  } catch {
    return false;
  }
};

// MARK: Rules — "if a fox comes at night, flash the lamp and tell me"

export function parseRule(text) {
  const s = text.toLowerCase();
  const has = (...w) => w.some((x) => s.includes(x));
  const species = PESTS.filter((p) => s.includes(p) || (p === 'gull' && s.includes('seagull')) || (p === 'rat' && has('mice', 'mouse')));
  let trigger;
  if (species.length || has('pest', 'animal')) trigger = { type: 'pest', species };
  else if (has('bird')) trigger = { type: 'pest', species: ['pigeon', 'gull'] };
  else if (has('person', 'someone', 'somebody', 'people', 'human', 'anyone')) trigger = { type: 'person' };
  else if (has('cat', 'dog', 'hedgehog', 'pet')) trigger = { type: 'friend' };
  else trigger = { type: 'motion' };

  const actions = [];
  if (has('scare', 'shoo', 'sound', 'noise', 'deter', 'chase')) actions.push('deter');
  if (has('light', 'lamp', 'flash', 'torch', 'strobe')) actions.push('lamp');
  if (has('notify', 'alert', 'tell me', 'ping', 'let me know', 'message', 'warn')) actions.push('notify');
  const webhook = text.split(/\s+/).find((w) => /^https?:\/\//.test(w)) ?? null;
  if (webhook || has('webhook', 'home assistant')) actions.push('webhook');
  if (!actions.length) actions.push('notify');

  let from = null, to = null;
  if (has('at night', 'overnight', 'after dark')) [from, to] = [21, 6];
  const t = s.replace(/midnight/g, '0am').replace(/noon/g, '12pm');
  const hours = [...t.matchAll(/(\d{1,2})\s*(am|pm)?/g)]
    .map(([, h, ap]) => { let n = Number(h); if (n > 24) return null; if (ap === 'pm' && n < 12) n += 12; if (ap === 'am' && n === 12) n = 0; return n % 24; })
    .filter((n) => n != null);
  if (hours.length >= 2 && has('between', 'from')) [from, to] = hours;
  else if (hours.length && s.includes('after')) [from, to] = [hours[0], 6];
  else if (hours.length && s.includes('before')) [from, to] = [6, hours[0]];

  return { id: crypto.randomUUID(), enabled: true, text, trigger, from, to, actions, webhook, cooldown: 60 };
}

export function ruleWhen(r) {
  const what = { pest: r.trigger.species?.length ? r.trigger.species.join(' / ') : 'any pest', person: 'person', friend: 'cat / dog / hedgehog', motion: 'movement' }[r.trigger.type];
  const pad = (n) => String(n).padStart(2, '0');
  return r.from != null && r.to != null ? `${what} · ${pad(r.from)}–${pad(r.to)}` : what;
}

export function ruleActive(r, date = new Date()) {
  if (!r.enabled) return false;
  if (r.from == null || r.to == null || r.from === r.to) return true;
  const h = date.getHours();
  return r.from < r.to ? h >= r.from && h < r.to : h >= r.from || h < r.to;
}
