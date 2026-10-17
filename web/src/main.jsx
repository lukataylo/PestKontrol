import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import './styles.css';
import { theme } from './theme.js';
import { BotFace } from './bot.jsx';
import { DotText, Glyph } from './dot.jsx';
import * as S from './sentry.js';
import { RoughFilter, Pulse } from './ui.jsx';
import { Watch, botState } from './views/Watch.jsx';
import { Ask, Player } from './views/Ask.jsx';
import { Log } from './views/Log.jsx';
import { Config } from './views/Config.jsx';
import { Onboarding } from './views/Onboarding.jsx';
import { clock, slasher } from './theme.js';

const TABS = [
  ['watch', 'eye', 'Watch'],
  ['ask', 'search', 'Ask'],
  ['log', 'list', 'Log'],
  ['config', 'sliders', 'Config'],
];

function App() {
  const [tab, setTab] = useState('watch');
  const [clip, setClip] = useState(null);
  theme.value; // re-render the whole tree on theme change

  useEffect(() => {
    if (S.onboarded.value) S.start();
  }, [S.onboarded.value]);

  if (!S.onboarded.value) return <><RoughFilter /><Onboarding /></>;

  return (
    <div class="shell">
      <RoughFilter />
      {tab === 'watch' && <Watch />}
      {tab === 'ask' && <Ask play={setClip} />}
      {tab === 'log' && <Log />}
      {tab === 'config' && <Config />}
      <nav class="tabbar" aria-label="Sections">
        {TABS.map(([id, icon, label]) => (
          <button key={id} class={tab === id ? 'on' : ''} onClick={() => { navigator.vibrate?.(5); setTab(id); }} aria-label={label} aria-current={tab === id ? 'page' : undefined}>
            <Glyph name={icon} pitch={2.6} color={tab === id ? (slasher() ? 'var(--red)' : 'var(--ink)') : 'var(--ghost)'} />
            <span class="dot" />
          </button>
        ))}
      </nav>
      {clip && <Player clip={clip} close={() => setClip(null)} />}
      {S.stealth.value && <Stealth />}
    </div>
  );
}

/// Near-black screen for long sessions; the bot dozes on and drifts so OLED doesn't burn.
function Stealth() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(id);
  }, []);
  const m = now.getMinutes();
  const st = botState();
  return (
    <div class="stealth" onClick={() => (S.stealth.value = false)} role="button" aria-label="Screen dimmed. Tap to wake.">
      <div class="inner" style={{ transform: `translate(${((m % 5) - 2) * 8}px, ${((m % 7) - 3) * 10}px)` }}>
        <div style={{ width: '200px' }}><BotFace mood={S.mood(st, S.armed.value, slasher())} /></div>
        <div class="row" style={{ gap: '8px' }}>
          <Pulse on={S.armed.value} />
          <DotText text={clock(now)} pitch={2.4} color="#ffffff" />
        </div>
      </div>
    </div>
  );
}

render(<App />, document.getElementById('app'));

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}
