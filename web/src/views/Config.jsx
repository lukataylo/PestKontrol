import { useState } from 'preact/hooks';
import { DotText, Glyph, Pet } from '../dot.jsx';
import { PESTS, FRIENDS, model } from '../detector.js';
import { PATTERNS, SOUND_INFO, VOICES } from '../sound.js';
import * as S from '../sentry.js';
import { THEMES, theme, slasher, load, save, grainURL } from '../theme.js';
import { Caption, Card, Panel, Stepper, Title, Toggle } from '../ui.jsx';
import { EngineCard } from './Engine.jsx';

/// Pick a pest's sound: every option with a one-line description and a preview.
export function SoundSheet({ species, close }) {
  const current = S.patternFor(species);
  const choose = (k) => {
    S.settings.value = { ...S.settings.value, patterns: { ...S.settings.value.patterns, [species]: k } };
    S.test(k);
  };
  return (
    <div class="sheet" role="dialog" aria-label={`Sound for ${species}`}>
      <div class="stack">
        <div class="row">
          <Pet kind={species} pitch={3} />
          <DotText text={`${species} SOUND`} pitch={3} />
          <span class="spacer" />
          <button class="close" onClick={close} aria-label="Done">✕</button>
        </div>
        <p class="body" style={{ fontSize: '13px' }}>Tap to choose and hear it. Turn the volume up.</p>
        {PATTERNS.map((k) => {
          const info = SOUND_INFO[k];
          const on = k === current;
          return (
            <Panel key={k} class="listrow" radius="18px" style={{ padding: '12px 14px', ...(on ? { borderColor: 'var(--red)' } : null) }}
              seed={k.length * 13} onClick={() => choose(k)}>
              <div class="row" style={{ gap: '14px', width: '100%' }}>
                <span class={`radio ${on ? 'on' : ''}`} aria-hidden="true" />
                <div class="stack" style={{ gap: '6px', flex: 1 }}>
                  <div class="row" style={{ gap: '8px' }}>
                    <DotText text={info.name} pitch={2.4} />
                    {info.high && <span class="chip" style={{ padding: '3px 7px' }}>High-pitched</span>}
                  </div>
                  <span class="blurb">{info.text}</span>
                </div>
                <button class="round" style={{ width: '40px', height: '40px' }} aria-label={`Preview ${info.name}`}
                  onClick={(e) => { e.stopPropagation(); S.test(k); }}>
                  <Glyph name="play" pitch={2} />
                </button>
              </div>
            </Panel>
          );
        })}
        <button class="primary press" onClick={close}><DotText text="DONE" pitch={3} color="#000000" /></button>
      </div>
    </div>
  );
}

export function PetGrid({ showSound = true }) {
  const s = S.settings.value;
  const [picking, setPicking] = useState(null);
  const set = (patch) => (S.settings.value = { ...s, ...patch });
  const toggle = (p) => set({ enabled: s.enabled.includes(p) ? s.enabled.filter((x) => x !== p) : [...s.enabled, p] });
  const cycle = (p, e) => {
    e.stopPropagation();
    setPicking(p);
  };
  const sl = slasher();
  return (
    <div class="grid2">
      {PESTS.map((p) => {
        const on = s.enabled.includes(p);
        const chip = showSound && (
          <button class="chip" style={{ alignSelf: 'flex-start', opacity: on ? 1 : 0.4 }} onClick={(e) => cycle(p, e)} aria-label={`Sound ${S.patternFor(p)}. Tap to choose.`}>
            <Glyph name="wave" pitch={1.5} />{SOUND_INFO[S.patternFor(p)]?.name ?? S.patternFor(p)}<span aria-hidden="true" style={{ opacity: 0.6 }}>▾</span>
          </button>
        );
        return sl ? (
          <Panel key={p} class={`pet art ${on ? '' : 'off'}`} radius="22px" seed={p.length * 7} onClick={() => toggle(p)}>
            <img src={`/slasher/${p}.png`} alt="" />
            <span class={`check ${on ? 'on' : ''}`} />
            <div class="meta">
              <span class="petname" style={{ color: on ? 'var(--ink)' : 'var(--ghost)' }}>{p.toUpperCase()}</span>
              {chip}
            </div>
          </Panel>
        ) : (
          <Panel key={p} class={`pet ${on ? '' : 'off'}`} radius="22px" onClick={() => toggle(p)}>
            <div class="row" style={{ alignItems: 'flex-start' }}>
              <Pet kind={p} pitch={4.4} dim={!on} />
              <span class="spacer" />
              <span class={`check ${on ? 'on' : ''}`} />
            </div>
            <DotText text={p} pitch={2.3} color={on ? undefined : 'var(--ghost)'} />
            {chip}
          </Panel>
        );
      })}
      {sl && (
        <Panel radius="22px" seed={40} style={{ minHeight: '150px', display: 'grid', placeItems: 'center' }}>
          <svg viewBox="0 0 100 70" width="80%" aria-hidden="true" style={{ filter: 'url(#rough)' }}>
            <circle cx="50" cy="35" r="17" fill="none" stroke="var(--red)" stroke-width="2.6" />
            <path d="M14 35H86M50 6V64" stroke="var(--red)" stroke-width="2" />
          </svg>
        </Panel>
      )}
      {picking && <SoundSheet species={picking} close={() => setPicking(null)} />}
    </div>
  );
}

export const Friends = ({ dim }) => (
  <div class="row" style={{ justifyContent: 'space-around' }}>
    {FRIENDS.map((f) => (
      <div key={f} class="stack" style={{ alignItems: 'center', gap: '10px' }}>
        <div style={{ height: '30px', display: 'flex', alignItems: 'flex-end' }}><Pet kind={f} pitch={3.2} dim={dim} /></div>
        <Caption>{f}</Caption>
      </div>
    ))}
  </div>
);

const Level = ({ n, color }) => (
  <div class="row" style={{ gap: '3px', alignItems: 'flex-end', width: '26px' }}>
    {[1, 2, 3].map((i) => (
      <div key={i} class="stack" style={{ gap: '3px' }}>
        {Array.from({ length: i }, (_, k) => <span key={k} style={{ width: '5px', height: '5px', borderRadius: '50%', background: color, opacity: i <= n ? 1 : 0.18 }} />)}
      </div>
    ))}
  </div>
);

export function ModePicker() {
  const s = S.settings.value;
  const pick = (m) => (S.settings.value = { ...s, mode: m });
  if (slasher()) {
    return (
      <Panel class="segmented" radius="18px" seed={33}>
        {Object.entries(S.MODES).map(([k, m]) => (
          <button key={k} class={s.mode === k ? 'on' : ''} onClick={() => pick(k)} aria-pressed={s.mode === k}>
            <Glyph name="wave" pitch={1.6 + m.level * 0.35} />{m.label}
          </button>
        ))}
      </Panel>
    );
  }
  return (
    <div class="modes">
      {Object.entries(S.MODES).map(([k, m]) => {
        const on = s.mode === k;
        return (
          <button key={k} class={`mode press ${on ? 'on' : ''}`} onClick={() => pick(k)} aria-pressed={on}>
            <Level n={m.level} color={on ? '#000' : 'var(--ink)'} />
            <div class="stack" style={{ gap: '8px' }}>
              <DotText text={m.label} pitch={3} color={on ? '#000000' : undefined} />
              <span class="blurb">{m.blurb}</span>
            </div>
          </button>
        );
      })}
      {s.mode === 'custom' && <Caption>Custom · fine-tuned</Caption>}
    </div>
  );
}

export function Config() {
  const s = S.settings.value;
  const t = S.tuning.value;
  const set = (patch) => (S.settings.value = { ...s, ...patch });
  const tune = (patch) => set({ mode: 'custom', custom: { ...t, ...patch } });
  const [fine, setFine] = useState(false);
  const [debug, setDebug] = useState(load('shoo.debug', false));
  const hh = (h) => `${String(h).padStart(2, '0')}:00`;
  const m = model.value;

  return (
    <div class="screen">
      <div class="stack">
        <Title text="CONFIG" />
        <Caption>Pests</Caption>
        <PetGrid />

        <Card title="Friends · never scared">
          <Friends dim={!s.protectLock} />
          <div class="row">
            <span class="text" style={{ fontSize: '12px' }}>Hold fire when a friend is in view</span>
            <span class="spacer" />
            <Toggle on={s.protectLock} label="Hold fire for friends" onChange={(on) => set({ protectLock: on })} />
          </div>
        </Card>

        <Caption style={{ marginTop: '6px' }}>Mode</Caption>
        <ModePicker />

        <Caption style={{ marginTop: '6px' }}>Theme</Caption>
        <div class="grid2">
          {Object.keys(THEMES).map((k) => (
            <button key={k} class="press stack" style={{ gap: '10px', alignItems: 'center' }} onClick={() => (theme.value = k)} aria-pressed={theme.value === k}>
              <div style={{
                width: '100%', height: '86px', borderRadius: '16px', display: 'grid', placeItems: 'center', overflow: 'hidden',
                background: k === 'nothing' ? '#000' : `${THEMES.slasher.black} ${''}`,
                backgroundImage: k === 'slasher' ? `url(${grainURL})` : 'radial-gradient(rgba(255,255,255,.1) .75px, transparent .9px)',
                backgroundSize: k === 'slasher' ? '256px' : '9px 9px',
                border: theme.value === k ? '2px solid var(--red)' : '1px solid var(--line)',
              }}>
                {k === 'nothing'
                  ? <div class="row" style={{ gap: '6px' }}><DotText text="SHOO" pitch={2.6} color="#ffffff" /><span style={{ width: '6px', height: '6px', borderRadius: '50%', background: THEMES.nothing.red }} /></div>
                  : <img src="/slasher/logo_shoo.png" alt="" style={{ height: '60px' }} />}
              </div>
              <Caption style={{ color: theme.value === k ? 'var(--ink)' : undefined }}>{k}</Caption>
            </button>
          ))}
        </div>

        <Card>
          <div class="row">
            <Glyph name="moon" pitch={3} />
            <div class="stack" style={{ gap: '6px' }}>
              <DotText text="QUIET NIGHTS" pitch={2.4} />
              <Caption>{hh(s.quietStart)} → {hh(s.quietEnd)} · log only</Caption>
            </div>
            <span class="spacer" />
            <Toggle on={s.quietHours} label="Quiet nights" onChange={(on) => set({ quietHours: on })} />
          </div>
        </Card>

        <Card>
          <button class="row" style={{ width: '100%' }} onClick={() => setFine(!fine)} aria-expanded={fine}>
            <DotText text="FINE-TUNE" pitch={2.4} />
            <span class="spacer" />
            <span style={{ transform: fine ? 'rotate(180deg)' : 'none', transition: 'transform .2s' }}><Glyph name="chevron" pitch={2.4} color="var(--dim)" /></span>
          </button>
          {fine && (
            <>
              <Stepper label="Certainty" value={`${Math.round(t.threshold * 100)}%`} dec={() => tune({ threshold: Math.max(0.15, +(t.threshold - 0.05).toFixed(2)) })} inc={() => tune({ threshold: Math.min(0.95, +(t.threshold + 0.05).toFixed(2)) })} />
              <Stepper label="Patience" value={String(t.confirm)} dec={() => tune({ confirm: Math.max(1, t.confirm - 1) })} inc={() => tune({ confirm: Math.min(8, t.confirm + 1) })} />
              <Stepper label="Rest" value={`${t.cooldown}S`} dec={() => tune({ cooldown: Math.max(10, t.cooldown - 15) })} inc={() => tune({ cooldown: Math.min(600, t.cooldown + 15) })} />
              <Stepper label="Loudness" value={`${Math.round(t.gain * 100)}%`} dec={() => tune({ gain: Math.max(0.1, +(t.gain - 0.1).toFixed(1)) })} inc={() => tune({ gain: Math.min(1, +(t.gain + 0.1).toFixed(1)) })} />
              <Stepper label="Quiet from" value={hh(s.quietStart)} dec={() => set({ quietStart: (s.quietStart + 23) % 24 })} inc={() => set({ quietStart: (s.quietStart + 1) % 24 })} />
              <Stepper label="Quiet until" value={hh(s.quietEnd)} dec={() => set({ quietEnd: (s.quietEnd + 23) % 24 })} inc={() => set({ quietEnd: (s.quietEnd + 1) % 24 })} />
              <Caption>Certainty: how sure before acting. Patience: checks in a row (~0.7 s each). Rest: pause after acting.</Caption>
            </>
          )}
        </Card>

        <Card><EngineCard /></Card>
        <Card>
          <div class="row">
            <Glyph name="lock" pitch={3} />
            <div class="stack" style={{ gap: '6px' }}>
              <DotText text="ON-DEVICE" pitch={2.4} />
              <Caption>MobileCLIP · nothing uploaded</Caption>
            </div>
          </div>
          <div class="row">
            <span class="text" style={{ fontSize: '12px' }}>Show what I see — raw labels on the camera</span>
            <span class="spacer" />
            <Toggle on={debug} label="Show raw labels" onChange={(on) => { setDebug(on); save('shoo.debug', on); }} />
          </div>
          <Caption>Hear every sound</Caption>
          <div class="row" style={{ gap: '8px', flexWrap: 'wrap' }}>
            {PATTERNSButtons()}
          </div>
          <button class="chip" style={{ alignSelf: 'flex-start' }} onClick={() => (S.onboarded.value = false)}>Replay intro</button>
        </Card>
      </div>
    </div>
  );
}

const PATTERNSButtons = () =>
  VOICES.map((p) => (
    <button key={p} class="chip press" onClick={() => S.test(p)} aria-label={`Play ${p}`}><Glyph name="play" pitch={1.5} />{p}</button>
  ));
