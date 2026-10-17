import { signal, effect } from '@preact/signals';

/// Nothing: black, white, one red. Slasher: soot, bone, blood.
export const THEMES = {
  nothing: { black: '#000000', panel: '#111111', ink: '#ffffff', red: '#d71921' },
  slasher: { black: '#090807', panel: '#0e0c0b', ink: '#ede6d4', red: '#e33c30' },
};

export const load = (key, fallback) => {
  try {
    const raw = localStorage.getItem(key);
    return raw == null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
};

export const save = (key, value) => {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* private mode: settings just won't persist */
  }
};

export const theme = signal(load('shoo.theme', 'nothing'));

effect(() => {
  document.documentElement.dataset.theme = theme.value;
  const p = THEMES[theme.value];
  for (const [k, v] of Object.entries(p)) document.documentElement.style.setProperty(`--${k}`, v);
  document.querySelector('meta[name=theme-color]')?.setAttribute('content', p.black);
  save('shoo.theme', theme.value);
});

/// Current palette. Reading it inside a component subscribes that component to theme changes.
export const pal = () => THEMES[theme.value];
export const slasher = () => theme.value === 'slasher';

export function rgba(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

/// Deterministic xorshift so a given panel always gets the same scuffs.
export function seeded(seed) {
  let s = (Math.imul(seed | 0, 0x9e3779b1) | 1) >>> 0;
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s / 4294967296;
  };
}

/// 256² grain tile, generated once, used by the Slasher background and camera.
export const grainURL = (() => {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  const r = seeded(7);
  for (let i = 0; i < 5200; i++) {
    const light = r() > 0.55;
    g.fillStyle = light ? `rgba(255,255,255,${0.03 + r() * 0.13})` : `rgba(0,0,0,${0.03 + r() * 0.47})`;
    const s = 0.6 + r() * 1.2;
    g.fillRect(r() * 256, r() * 256, s, s);
  }
  return c.toDataURL('image/png');
})();
document.documentElement.style.setProperty('--grain', `url(${grainURL})`);

export const clock = (d) => d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
export const stamp = (d) =>
  `${d.toLocaleDateString([], { day: '2-digit', month: 'short' })} · ${clock(d)}`;
