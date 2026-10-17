import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { BotFace, BotSpeech } from '../bot.jsx';
import { DotText, Glyph } from '../dot.jsx';
import { model, DARK_LUMA } from '../detector.js';
import * as S from '../sentry.js';
import { all, revision } from '../store.js';
import { clock, pal, slasher } from '../theme.js';
import { Panel, Pulse, RoundButton, Title, Splatter, Chip } from '../ui.jsx';
import { load } from '../theme.js';

export function botState() {
  const m = model.value;
  if (S.running.value && m.phase !== 'ready') return { kind: 'loading' };
  return S.status.value;
}

export function Watch() {
  const st = botState();
  const f = S.frame.value;
  const sl = slasher();
  const mood = S.mood(st, S.armed.value, sl);
  const gaze = f?.box && (f.confidence >= S.tuning.value.threshold * 0.6 || f.guardedConfidence >= 0.4)
    ? (f.box.x + f.box.w / 2 - 0.5) * 2 : null;

  return (
    <div class="screen fixed">
      <Header />
      <Panel seed={5} splat={sl ? 'br' : null} radius="28px" style={mood === 'angry' && !sl ? { borderColor: 'var(--red)', borderWidth: '2px' } : null}>
        <div class="stack" style={{ gap: '16px' }}>
          <BotFace mood={mood} gaze={gaze} />
          <BotSpeech text={S.line(st, S.armed.value, sl)} />
        </div>
      </Panel>
      <Viewport />
      <Controls />
    </div>
  );
}

function Header() {
  const [now, setNow] = useState(new Date());
  const [battery, setBattery] = useState(null);
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 10_000);
    navigator.getBattery?.().then((b) => {
      const upd = () => setBattery(`${b.charging ? '+' : ''}${Math.round(b.level * 100)}%`);
      upd();
      b.onlevelchange = b.onchargingchange = upd;
    });
    return () => clearInterval(id);
  }, []);
  return (
    <div class="row" style={{ alignItems: slasher() ? 'flex-start' : 'center' }}>
      <Title text="SHOO" />
      {!slasher() && <Pulse on={S.armed.value} />}
      <span class="spacer" />
      <span class="caption" style={{ letterSpacing: '0.05em' }}>{clock(now)}{battery ? `  ${battery}` : ''}</span>
    </div>
  );
}

function Viewport() {
  const video = useRef();
  const overlay = useRef();
  const f = S.frame.value;
  const sl = slasher();
  const p = pal();
  const debug = load('shoo.debug', false);
  const m = model.value;

  useEffect(() => {
    if (video.current && S.stream.value) {
      video.current.srcObject = S.stream.value;
      video.current.play().catch(() => {});
    }
  }, [S.stream.value]);

  // Brackets + label, mapped through object-fit: cover.
  useLayoutEffect(() => {
    const c = overlay.current, v = video.current;
    if (!c) return;
    const w = c.clientWidth, h = c.clientHeight, dpr = Math.min(2, devicePixelRatio || 1);
    c.width = w * dpr;
    c.height = h * dpr;
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    g.clearRect(0, 0, w, h);
    g.strokeStyle = 'rgba(255,255,255,0.35)';
    g.lineWidth = 1;
    const cy = sl ? 40 : h / 2;
    g.beginPath(); g.moveTo(w / 2 - 7, cy); g.lineTo(w / 2 + 7, cy); g.moveTo(w / 2, cy - 7); g.lineTo(w / 2, cy + 7); g.stroke();

    const vw = v?.videoWidth || 9, vh = v?.videoHeight || 16;
    const scale = Math.max(w / vw, h / vh), dw = vw * scale, dh = vh * scale, ox = (w - dw) / 2, oy = (h - dh) / 2;
    const show = f?.box && (f.confidence >= S.tuning.value.threshold * 0.6 || f.guardedConfidence >= 0.45);
    const brackets = (x, y, bw, bh, color, len, lw) => {
      const l = Math.min(len, bw / 3, bh / 3);
      g.strokeStyle = color; g.lineWidth = lw; g.lineCap = sl ? 'square' : 'round';
      g.beginPath();
      g.moveTo(x, y + l); g.lineTo(x, y); g.lineTo(x + l, y);
      g.moveTo(x + bw - l, y); g.lineTo(x + bw, y); g.lineTo(x + bw, y + l);
      g.moveTo(x + bw, y + bh - l); g.lineTo(x + bw, y + bh); g.lineTo(x + bw - l, y + bh);
      g.moveTo(x + l, y + bh); g.lineTo(x, y + bh); g.lineTo(x, y + bh - l);
      g.stroke();
    };
    if (show) {
      const b = f.box;
      const guarded = f.guardedConfidence > f.confidence;
      const x = ox + b.x * dw, y = oy + b.y * dh, bw = b.w * dw, bh = b.h * dh;
      brackets(x, y, bw, bh, guarded ? p.ink : p.red, 20, 2.5);
      const label = (guarded ? f.guarded : f.species)?.toUpperCase() + (sl || guarded ? '' : ` ${Math.round(f.confidence * 100)}%`);
      g.font = `700 12px ${getComputedStyle(document.body).getPropertyValue('--mono')}`;
      const tw = g.measureText(label).width + 22;
      const lx = Math.min(Math.max(x + bw / 2 - tw / 2, 8), w - tw - 8), ly = Math.max(y - 30, 8);
      g.fillStyle = guarded ? p.ink : p.red;
      if (sl || !g.roundRect) g.fillRect(lx, ly, tw, 22);
      else { g.beginPath(); g.roundRect(lx, ly, tw, 22, 11); g.fill(); }
      g.fillStyle = sl || guarded ? '#000' : '#fff';
      g.fillText(label, lx + 11, ly + 15);
    } else if (sl && S.running.value) {
      brackets(w * 0.275, h * 0.32, w * 0.45, h * 0.48, 'rgba(237,230,212,0.85)', 26, 2);
    }
  });

  const armed = S.armed.value;
  return (
    <div class={`viewport ${armed && !sl ? 'armed' : ''}`}>
      {S.stream.value && <video ref={video} muted playsInline autoplay />}
      {sl && <div class="grainlayer" />}
      {sl && <Splatter anchor="l" seed={8} amount={1.4} />}
      {sl && <Splatter anchor="bl" seed={9} amount={1.2} />}
      <canvas ref={overlay} class="overlay" aria-hidden="true" />
      {sl && <div class="live" style={{ opacity: S.running.value ? 1 : 0.3 }}><i />LIVE</div>}
      {!S.stream.value && (
        <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', textAlign: 'center', padding: '24px' }}>
          {S.cameraError.value ? (
            <div class="stack" style={{ alignItems: 'center' }}>
              <DotText text="NO CAMERA" pitch={3.5} />
              <p class="body">{S.cameraError.value === 'denied' ? 'Allow camera access for this site in your browser settings, then reload.' : S.cameraError.value}</p>
              <button class="chip ink" onClick={S.start}>Try again</button>
            </div>
          ) : (
            <button class="chip ink" onClick={S.start}>Start camera</button>
          )}
        </div>
      )}
      {S.running.value && m.phase !== 'ready' && (
        <div style={{ position: 'absolute', left: '16px', right: '16px', bottom: '16px' }} class="stack">
          <span class="caption">{m.phase === 'error' ? `Model failed: ${m.error}` : `Loading on-device model · ${Math.round(m.progress * 100)}%`}</span>
          <div class="progress"><i style={{ width: `${m.progress * 100}%` }} /></div>
        </div>
      )}
      <div class="vchips">
        {f && f.luma < DARK_LUMA && <Chip>Night</Chip>}
        {S.isQuiet() && <Chip>Quiet</Chip>}
      </div>
      {debug && f && (
        <div class="debug">
          {f.moving && <div style={{ color: 'var(--red)' }}>MOTION</div>}
          {Object.entries(f.labels).sort((a, b) => b[1] - a[1]).slice(0, 4).map(([k, v]) => <div key={k}>{k} {v.toFixed(2)}</div>)}
          <div style={{ opacity: 0.6 }}>{m.device}</div>
        </div>
      )}
    </div>
  );
}

function Controls() {
  const [today, setToday] = useState([0, 0]);
  const rev = revision.value;
  useEffect(() => {
    const start = new Date(); start.setHours(0, 0, 0, 0);
    all('sightings').then((s) => {
      const t = s.filter((x) => x.at >= start);
      setToday([t.length, t.filter((x) => x.outcome === 'fired').length]);
    });
  }, [rev]);
  const stat = (icon, n, label) => (
    <div class="row" style={{ gap: '7px' }} aria-label={`${n} ${label}`}>
      <Glyph name={icon} pitch={2} color="var(--dim)" />
      <DotText text={String(n)} pitch={3} />
    </div>
  );
  return (
    <div class="row" style={{ paddingBottom: '2px' }}>
      <div class="row" style={{ gap: '16px' }}>
        {stat('eye', today[0], 'visits today')}
        {stat('speaker', today[1], 'deterred today')}
      </div>
      <span class="spacer" />
      {S.torchSupported.value && (
        <RoundButton icon="bulb" label={S.torch.value ? 'Lamp off' : 'Lamp on'} on={S.torch.value} onClick={() => S.setTorch(!S.torch.value)} />
      )}
      <RoundButton icon="moon" label="Dim screen" onClick={() => (S.stealth.value = true)} />
      <RoundButton icon="power" big armed={S.armed.value} label={S.armed.value ? 'Disarm' : 'Arm'}
        onClick={() => { navigator.vibrate?.(20); S.setArmed(!S.armed.value); }} />
    </div>
  );
}
