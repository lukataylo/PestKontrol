import { useEffect, useState } from 'preact/hooks';
import { DotText, Glyph } from '../dot.jsx';
import { cloud, cloudStatus, refreshStatus } from '../cloud.js';
import { Caption, Toggle } from '../ui.jsx';

/// Opt-in VAST archive + NVIDIA verification. Off by default; explains exactly what leaves the phone.
export function CloudCard() {
  const c = cloud.value;
  const st = cloudStatus.value;
  const [key, setKey] = useState(c.key);
  const set = (patch) => (cloud.value = { ...cloud.value, ...patch });
  useEffect(() => { refreshStatus(); }, [c.key, c.enabled]);

  const dot = (ok) => <span class="statusdot" style={{ background: ok ? 'var(--red)' : 'var(--ghost)' }} />;
  return (
    <div class="stack" style={{ gap: '12px' }}>
      <div class="row" style={{ gap: '10px' }}>
        <Glyph name="bolt" pitch={2.2} color="var(--red)" />
        <DotText text="CLOUD BOOST" pitch={2.2} />
        <span class="spacer" />
        <Toggle on={c.enabled} label="Cloud Boost" onChange={(on) => set({ enabled: on })} />
      </div>
      <p class="body" style={{ fontSize: '12px' }}>
        Sends a snapshot of each confirmed visit — never live video — to this server. <b>NVIDIA</b> Cosmos Reason
        double-checks and describes it, Nemotron makes it searchable, and <b>VAST</b> archives it across all your cameras.
      </p>
      {c.enabled && (
        <>
          <input class="hook" type="password" placeholder="Cloud key" value={key} autoComplete="off"
            onInput={(e) => setKey(e.currentTarget.value)} onBlur={() => set({ key: key.trim() })} aria-label="Cloud key" />
          <input class="hook" placeholder="Camera name" value={c.device} maxLength={40}
            onInput={(e) => set({ device: e.currentTarget.value.replace(/[^\w\- ]/g, '') })} aria-label="Camera name" />
          <div class="row">
            <span class="text" style={{ fontSize: '12px' }}>Only scare once NVIDIA confirms (adds ~2 s)</span>
            <span class="spacer" />
            <Toggle on={c.verifyFirst} label="Verify before scaring" onChange={(on) => set({ verifyFirst: on })} />
          </div>
          <div class="stack" style={{ gap: '6px' }}>
            <div class="row" style={{ gap: '8px' }}>{dot(st?.authorised)}<Caption>{st?.error ? st.error : !st?.enabled ? 'Server: Cloud Boost not set up' : st.authorised ? 'Key accepted' : 'Enter the cloud key'}</Caption></div>
            <div class="row" style={{ gap: '8px' }}>{dot(st?.vast?.connected)}<Caption>VAST · {st?.vast?.connected ? `${st.vast.mode.toUpperCase()} ${st.vast.where}` : 'not connected (local disk)'}</Caption></div>
            <div class="row" style={{ gap: '8px' }}>{dot(st?.nvidia?.connected)}<Caption>NVIDIA · {st?.nvidia?.connected ? st.nvidia.models.vision.split('/')[1] : 'no API key on server'}</Caption></div>
          </div>
        </>
      )}
    </div>
  );
}
