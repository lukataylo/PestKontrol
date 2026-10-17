import { useLayoutEffect, useRef } from 'preact/hooks';
import { DotText, Glyph } from './dot.jsx';
import { pal, seeded, slasher } from './theme.js';

export const Caption = ({ children, style }) => <div class="caption" style={style}>{children}</div>;

/// Blood splatter bleeding in from an edge (Slasher only), seeded so it never jumps.
export function Splatter({ anchor = 'br', seed = 1, amount = 1 }) {
  const ref = useRef();
  const red = pal().red;
  useLayoutEffect(() => {
    const c = ref.current;
    const w = c.clientWidth, h = c.clientHeight;
    const dpr = Math.min(2, devicePixelRatio || 1);
    c.width = w * dpr;
    c.height = h * dpr;
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    const r = seeded(seed);
    const origin = () => {
      switch (anchor) {
        case 'bl': return [r() * w * 0.35, h - r() * h * 0.25];
        case 'l': return [r() * 14, r() * h];
        case 'tr': return [w - r() * w * 0.3, r() * h * 0.25];
        default: return [w - r() * w * 0.35, h - r() * h * 0.3];
      }
    };
    const flip = anchor === 'l' || anchor === 'bl';
    g.lineCap = 'round';
    for (let i = 0; i < 28 * amount; i++) {
      const [x, y] = origin();
      const a = -2.7 + r() * 0.5 + (flip ? Math.PI * 0.85 : 0), len = 8 + r() * 62;
      g.strokeStyle = red;
      g.globalAlpha = 0.4 + r() * 0.55;
      g.lineWidth = 0.5 + r() * 2.7;
      g.beginPath();
      g.moveTo(x, y);
      g.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len);
      g.stroke();
    }
    for (let i = 0; i < 90 * amount; i++) {
      const [x, y] = origin();
      const s = r() > 0.85 ? 4 + r() * 7 : 0.8 + r() * 2.2;
      g.globalAlpha = 0.35 + r() * 0.6;
      g.fillStyle = red;
      g.beginPath();
      g.ellipse(x, y, s / 2, (s / 2) * (0.6 + r() * 0.7), 0, 0, Math.PI * 2);
      g.fill();
    }
  }, [anchor, seed, amount, red]);
  return <canvas ref={ref} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }} aria-hidden="true" />;
}

/// The theme's surface: thin-lined in Nothing, chipped + splattered in Slasher.
export function Panel({ children, splat, seed = 1, class: cls = '', style, onClick, radius }) {
  return (
    <div class={`panel ${cls}`} style={{ ...(radius ? { borderRadius: radius } : null), ...style }} onClick={onClick}>
      {slasher() && splat && <div class="splat"><Splatter anchor={splat} seed={seed} /></div>}
      {children}
      <div class="rough" />
    </div>
  );
}

export const Card = ({ title, children, ...rest }) => (
  <Panel {...rest}>
    <div class="stack">
      {title && <Caption>{title}</Caption>}
      {children}
    </div>
  </Panel>
);

export const Chip = ({ children, kind = '', ...rest }) => <span class={`chip ${kind}`} {...rest}>{children}</span>;

export function Toggle({ on, onChange, label }) {
  return (
    <button
      class={`toggle ${on ? 'on' : ''}`}
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={() => { navigator.vibrate?.(8); onChange(!on); }}
    />
  );
}

export function Stepper({ label, value, dec, inc }) {
  return (
    <div class="row">
      <span class="caption" style={{ color: 'var(--ink)' }}>{label}</span>
      <span class="spacer" />
      <div class="stepper">
        <button aria-label={`Less ${label}`} onClick={dec}>−</button>
        <span class="val"><DotText text={value} pitch={3} /></span>
        <button aria-label={`More ${label}`} onClick={inc}>+</button>
      </div>
    </div>
  );
}

export function RoundButton({ icon, label, on, onClick, big, armed, fg }) {
  const p = pal();
  const color = fg ?? (big ? (armed ? '#ffffff' : '#000000') : on ? '#000000' : p.ink);
  return (
    <button class={`round ${on ? 'on' : ''} ${big ? 'big' : ''} ${armed ? 'armed' : ''}`} aria-label={label} onClick={onClick}>
      <Glyph name={icon} pitch={big ? 3.05 : 2.65} color={color} />
    </button>
  );
}

/// Screen headline: dot type in Nothing; brush logo or grunge type in Slasher.
export function Title({ text }) {
  if (!slasher()) return <DotText text={text} pitch={text === 'SHOO' ? 4 : 6} />;
  if (text === 'SHOO') return <img class="logo" src="/slasher/logo_shoo.png" alt="SHOO" />;
  if (text === 'CONFIG') return <img class="logo" style={{ height: '112px' }} src="/slasher/logo_config.png" alt="CONFIG" />;
  return <h1 class="slasher-title">{text}</h1>;
}

export const Pulse = ({ on }) => <span class={`pulse ${on ? 'on' : ''}`} />;

/// SVG filter that chews up Slasher borders. Mounted once.
export const RoughFilter = () => (
  <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden="true">
    <filter id="rough">
      <feTurbulence type="fractalNoise" baseFrequency="0.06" numOctaves="2" seed="4" result="n" />
      <feDisplacementMap in="SourceGraphic" in2="n" scale="3.5" />
    </filter>
  </svg>
);
