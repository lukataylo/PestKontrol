import { useEffect, useRef, useState } from 'preact/hooks';
import { DotText } from './dot.jsx';
import { pal, rgba, slasher } from './theme.js';

// 29×13 LED face, ported 1:1 from the iOS BotRenderer.
const COLS = 29, ROWS = 13;
const EYE_Y = 6, EYES = [8, 20], MOUTH_X = 14, MOUTH_Y = 11;

function renderer(mood, t, gaze, hollow) {
  const p = t % 4.2;
  const open = p < 0.16 ? Math.max(0.08, Math.abs(p - 0.08) / 0.08) : 1;
  let look = [0, 0];
  if (gaze != null) look = [Math.max(-1.6, Math.min(1.6, gaze * 2)), 0];
  else if (mood === 'idle') look = [1.5 * Math.sin(t * 0.7), 0.6 * Math.sin(t * 0.45)];
  else if (mood === 'smug') look = [1.4, 0.8];

  const blob = (dx, dy, rx, ry) =>
    ry < 0.7 ? Math.abs(dy) < 0.5 && Math.abs(dx) <= 3 : Math.abs(dx / rx) ** 4 + Math.abs(dy / ry) ** 4 <= 1;
  const pupil = (dx, dy, r = 1.05) => (dx - look[0]) ** 2 + (dy - look[1]) ** 2 <= r * r;
  const arc = (dx, dy, base, curve, half = 3, w = 0.55) => Math.abs(dy - (base + curve * dx * dx)) < w && Math.abs(dx) <= half;

  function eye(dx, dy, left) {
    switch (mood) {
      case 'idle': {
        const ry = 3.5 * open;
        if (!blob(dx, dy, 3.5, ry)) return null;
        if (hollow && ry > 1.5) return blob(dx - look[0] * 0.4, dy - look[1] * 0.4, 2.4, ry - 1.1) ? 0 : 1;
        return ry > 1.5 && pupil(dx, dy) ? 0 : 1;
      }
      case 'suspicious': {
        const ry = (left ? 1.6 : 3.2) * open;
        if (!left && Math.abs(dy + 5) < 0.5 && Math.abs(dx) <= 2.5) return 1;
        if (!blob(dx, dy, 3.5, ry)) return null;
        return ry > 1.5 && pupil(dx, dy, 0.9) ? 2 : 1;
      }
      case 'angry': {
        const inner = left ? dx : -dx;
        const brow = -4.4 + 0.38 * (inner + 3);
        if (Math.abs(dy - brow) < 0.55 && Math.abs(dx) <= 3.2) return 1;
        if (!blob(dx, dy, 3.5, 3.3) || dy <= brow + 0.7) return null;
        return pupil(dx, dy, 0.9) ? 2 : 1;
      }
      case 'surprised':
        if (Math.abs(dy + 5) < 0.5 && Math.abs(dx) <= 2) return 1;
        if (!blob(dx, dy, 3.5, 3.6)) return null;
        return pupil(dx, dy, 0.6) ? 0 : 1;
      case 'happy':
        return arc(dx, dy, -1.2, 0.32, 3, 0.8) ? 1 : null;
      case 'smug':
        if (!blob(dx, dy, 3.5, 3.3) || dy < -0.5) return null;
        return pupil(dx, dy, 0.9) ? 0 : 1;
      case 'sleepy':
        return arc(dx, dy, 1, -0.14) ? 1 : null;
      case 'dead':
        return Math.abs(Math.abs(dx) - Math.abs(dy)) < 0.5 && Math.abs(dx) <= 2.5 && Math.abs(dy) <= 2.5 ? 1 : null;
    }
    return null;
  }

  function mouth(dx, dy) {
    switch (mood) {
      case 'idle':
      case 'dead':
        return Math.abs(dy) < 0.5 && Math.abs(dx) <= 2 ? 1 : null;
      case 'suspicious':
        return Math.abs(dy - 0.3 * dx) < 0.5 && Math.abs(dx) <= 2.5 ? 1 : null;
      case 'angry': {
        const ry = 0.6 + 1.2 * Math.abs(Math.sin(t * 9));
        if (Math.abs(dx / 3.2) ** 4 + Math.abs(dy / ry) ** 4 > 1) return null;
        return Math.abs(dy) < ry - 0.9 && Math.abs(dx) < 2.2 ? 0 : 1;
      }
      case 'surprised': {
        const r = Math.hypot(dx, dy);
        return r > 0.6 && r < 1.6 ? 1 : null;
      }
      case 'happy':
      case 'smug':
        return arc(dx, dy, 0.6, -0.09, 3.5) ? 1 : null;
      case 'sleepy':
        return Math.abs(dy) < 0.5 && Math.abs(dx) <= 1 ? 1 : null;
    }
    return null;
  }

  const Z = ['####', '..#.', '.#..', '####'];
  return (x, y) => {
    for (let i = 0; i < 2; i++) {
      const dx = x - EYES[i], dy = y - EYE_Y;
      if (Math.abs(dx) <= 4 && Math.abs(dy) <= 5.5) {
        const v = eye(dx, dy, i === 0);
        if (v != null) return v;
      }
    }
    const m = mouth(x - MOUTH_X, y - MOUTH_Y);
    if (m != null) return m;
    if (mood === 'sleepy') {
      const rise = Math.floor((t % 2.4) / 0.8);
      const lx = x - 25, ly = y - (2 - rise);
      if (lx >= 0 && lx < 4 && ly >= 0 && ly < 4 && Z[ly][lx] === '#') return 2;
    }
    return 0;
  };
}

/// mood: idle | suspicious | angry | surprised | happy | smug | sleepy | dead
export function BotFace({ mood, gaze = null, width = '100%' }) {
  const ref = useRef();
  const props = useRef();
  const p = pal();
  props.current = { mood, gaze, p, hollow: slasher() };

  useEffect(() => {
    const c = ref.current;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    let raf, last = 0;
    const draw = (now) => {
      raf = requestAnimationFrame(draw);
      if (now - last < (reduce ? 1000 : 33)) return;
      last = now;
      const { mood, gaze, p, hollow } = props.current;
      const dpr = Math.min(3, devicePixelRatio || 1);
      const w = c.clientWidth, h = (w * ROWS) / COLS;
      if (c.width !== Math.round(w * dpr)) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
      const g = c.getContext('2d');
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, w, h);
      const pitch = w / COLS, d = pitch * 0.74, inset = (pitch - d) / 2;
      const px = renderer(mood, reduce ? 1 : now / 1000, gaze, hollow);
      const angry = mood === 'angry';
      const tint = angry ? p.red : p.ink;
      const pupil = hollow ? p.ink : p.red;
      g.shadowColor = angry && hollow ? rgba(p.red, 0.8) : 'transparent';
      g.shadowBlur = angry && hollow ? 10 : 0;
      for (let y = 0; y < ROWS; y++) {
        for (let x = 0; x < COLS; x++) {
          const v = px(x, y);
          g.fillStyle = v === 1 ? tint : v === 2 ? pupil : rgba(p.ink, 0.07);
          g.beginPath();
          g.arc(x * pitch + inset + d / 2, y * pitch + inset + d / 2, d / 2, 0, Math.PI * 2);
          g.fill();
        }
      }
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, []);

  return <canvas ref={ref} aria-hidden="true" style={{ width, aspectRatio: `${COLS} / ${ROWS}`, display: 'block' }} />;
}

function wrap(text, max) {
  const lines = [];
  let cur = '';
  for (const w of text.toUpperCase().split(' ').filter(Boolean)) {
    if (!cur) cur = w;
    else if (cur.length + 1 + w.length <= max) cur += ' ' + w;
    else { lines.push(cur); cur = w; }
  }
  if (cur) lines.push(cur);
  return lines;
}

/// Typewriter speech in dot type, two lines, blinking cursor.
export function BotSpeech({ text, pitch = 2.5, max = 20 }) {
  const [shown, setShown] = useState({ text, at: performance.now() });
  const [, tick] = useState(0);
  useEffect(() => setShown({ text, at: performance.now() }), [text]);
  useEffect(() => {
    const id = setInterval(() => tick((n) => n + 1), 40);
    return () => clearInterval(id);
  }, []);
  const lines = wrap(shown.text, max);
  let left = Math.floor((performance.now() - shown.at) / 30);
  const total = lines.reduce((a, l) => a + l.length, 0);
  const visible = lines.map((l) => { const s = l.slice(0, Math.max(0, left)); left -= l.length; return s; });
  const cursorLine = Math.max(0, lines.findIndex((l, i) => visible[i].length < l.length));
  const typing = visible.join('').length < total;
  const blink = typing || Math.floor(performance.now() / 400) % 2 === 0;
  const cl = typing ? cursorLine : Math.max(0, lines.length - 1);
  return (
    <div class="speech" role="status" aria-label={shown.text} style={{ gap: `${pitch * 3}px` }}>
      {[0, 1].map((i) => (
        <div key={i} style={{ height: `${pitch * 7}px` }}>
          <DotText text={(visible[i] ?? '') + (blink && i === cl ? '_' : '')} pitch={pitch} />
        </div>
      ))}
    </div>
  );
}
