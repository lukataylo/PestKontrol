import { useLayoutEffect, useRef } from 'preact/hooks';
import { FONT, GLYPHS, PETS } from './dotdata.js';
import { pal, rgba } from './theme.js';

export { GLYPHS, PETS };

/// 5×7 type → rows of a bitmap, one blank column between characters.
export function textRows(text) {
  const chars = [...String(text).toUpperCase()];
  return Array.from({ length: 7 }, (_, r) =>
    chars.map((ch) => (FONT[ch] ?? FONT['?'])[r]).join(' '),
  );
}

/// Canvas can't read CSS variables, so map the theme's names to real colours.
function resolve(c, p) {
  if (!c || !c.startsWith('var(')) return c;
  return { 'var(--ink)': p.ink, 'var(--red)': p.red, 'var(--dim)': rgba(p.ink, 0.62), 'var(--ghost)': rgba(p.ink, 0.24) }[c] ?? p.ink;
}

/// Bitmap drawn as dots. `#` ink, `o` accent, `-` half ink, anything else off.
export function Dots({ rows, pitch = 3, color, accent, ghost = false, dim = false, label, style, class: cls }) {
  const ref = useRef();
  const p = pal();
  const ink = resolve(color, p) ?? p.ink;
  const red = resolve(accent, p) ?? p.red;
  const cols = Math.max(0, ...rows.map((r) => r.length));

  useLayoutEffect(() => {
    const c = ref.current;
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    c.width = Math.ceil(cols * pitch * dpr);
    c.height = Math.ceil(rows.length * pitch * dpr);
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    const d = pitch * 0.8, inset = (pitch - d) / 2;
    const fade = (a) => (ink.startsWith('#') ? rgba(ink, a) : ink);
    const main = dim ? fade(0.22) : ink;
    rows.forEach((row, y) => {
      [...row].forEach((ch, x) => {
        let fill = null;
        if (ch === '#') fill = main;
        else if (ch === '-') fill = fade(dim ? 0.1 : 0.45);
        else if (ch === 'o') fill = dim ? fade(0.22) : red;
        else if (ghost) fill = fade(0.08);
        if (!fill) return;
        g.fillStyle = fill;
        g.beginPath();
        g.arc(x * pitch + inset + d / 2, y * pitch + inset + d / 2, d / 2, 0, Math.PI * 2);
        g.fill();
      });
    });
  }, [rows.join('|'), pitch, ink, red, ghost, dim]);

  return (
    <canvas
      ref={ref}
      class={cls}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : 'true'}
      style={{ width: `${cols * pitch}px`, height: `${rows.length * pitch}px`, display: 'block', ...style }}
    />
  );
}

export const DotText = ({ text, pitch = 3, ...rest }) => <Dots rows={textRows(text)} pitch={pitch} label={String(text)} {...rest} />;
export const Glyph = ({ name, pitch = 2.6, ...rest }) => <Dots rows={GLYPHS[name]} pitch={pitch} {...rest} />;
export const Pet = ({ kind, pitch = 3, ...rest }) => <Dots rows={PETS[kind]} pitch={pitch} {...rest} />;
