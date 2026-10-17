import { useState } from 'preact/hooks';
import { DotText, Glyph } from '../dot.jsx';
import { model, installModel } from '../detector.js';
import * as S from '../sentry.js';
import { Caption, Toggle } from '../ui.jsx';

const ENGINES = [['auto', 'AUTO'], ['gpu', 'GPU'], ['cpu', 'CPU']];

/// Install / status / retry for the on-device AI. Appears on the welcome screen,
/// in Config, and over the camera when something went wrong.
export function EngineCard({ compact = false }) {
  const m = model.value;
  const [copied, setCopied] = useState(false);
  const pct = Math.round((m.phase === 'ready' ? 1 : m.progress) * 100);
  const status = {
    idle: 'Not installed · ~70 MB, downloaded once',
    loading: m.progress >= 0.99 ? `Starting${m.trying ? ` on ${m.trying}` : ''}…` : `Downloading · ${pct}% of ~70 MB`,
    ready: `Ready · runs on ${m.device?.startsWith('gpu') ? 'GPU' : 'CPU'} · works offline`,
    error: 'Could not start on this device',
  }[m.phase];

  return (
    <div class="stack" style={{ gap: '12px' }}>
      <div class="row" style={{ gap: '10px' }}>
        <Glyph name={m.phase === 'ready' ? 'check' : m.phase === 'error' ? 'bolt' : 'eye'} pitch={2.2}
          color={m.phase === 'error' ? 'var(--red)' : m.phase === 'ready' ? 'var(--red)' : 'var(--ink)'} />
        <DotText text="AI ENGINE" pitch={2.2} />
        <span class="spacer" />
        {!compact && (
          <div class="row" style={{ gap: '4px' }} role="radiogroup" aria-label="Engine">
            {ENGINES.map(([k, label]) => (
              <button key={k} class={`chip ${m.engine === k ? 'ink' : ''}`} role="radio" aria-checked={m.engine === k}
                disabled={m.phase === 'loading'} onClick={() => installModel({ engine: k })}>{label}</button>
            ))}
          </div>
        )}
      </div>
      <Caption>{status}</Caption>
      {(m.phase === 'loading' || m.phase === 'ready') && <div class="progress"><i style={{ width: `${pct}%` }} /></div>}

      {m.phase === 'error' && (
        <>
          <div class="errbox">{m.error}</div>
          <div class="row" style={{ gap: '8px', flexWrap: 'wrap' }}>
            <button class="chip solid press" onClick={() => installModel()}>Retry</button>
            <button class="chip press" onClick={() => installModel({ engine: 'cpu' })}>Use CPU</button>
            <button class="chip press" onClick={() => installModel({ clearCache: true })}>Re-download</button>
            <button class="chip press" onClick={async () => {
              try { await navigator.clipboard.writeText(`SHOO engine error\n${navigator.userAgent}\n${m.error}`); setCopied(true); } catch { /* denied */ }
            }}>{copied ? 'Copied' : 'Copy error'}</button>
          </div>
          <div class="row">
            <span class="text" style={{ fontSize: '12px' }}>Basic mode: scare on any movement</span>
            <span class="spacer" />
            <Toggle on={S.settings.value.motionScare} label="Scare on any movement"
              onChange={(on) => (S.settings.value = { ...S.settings.value, motionScare: on })} />
          </div>
        </>
      )}

      {m.phase === 'idle' && (
        <button class="primary press" style={{ height: '52px' }} onClick={() => installModel()}>
          <DotText text="INSTALL AI ENGINE" pitch={2.6} color="#000000" />
        </button>
      )}
      {m.phase === 'ready' && !compact && (
        <button class="chip press" style={{ alignSelf: 'flex-start' }} onClick={() => installModel({ clearCache: true })}>Reinstall</button>
      )}
    </div>
  );
}
