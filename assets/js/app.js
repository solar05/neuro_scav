// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import "./gnome";

// ── Rarity flash overlay ──
function triggerRarityFlash(rarity) {
  const flash = document.getElementById('rarity-flash');
  if (!flash) return;
  flash.className = `rarity-flash flash-${rarity}`;
  void flash.offsetWidth;
  flash.classList.add('flash-active');
  setTimeout(() => { flash.className = 'rarity-flash'; }, 900);
}

// ── Screen shake (epic) ──
function triggerScreenShake() {
  document.body.classList.remove('screen-shake');
  void document.body.offsetWidth;
  document.body.classList.add('screen-shake');
  setTimeout(() => document.body.classList.remove('screen-shake'), 400);
}

// ── Haptic feedback (mobile only) ──
function vibrate(pattern) {
  if (navigator.vibrate) navigator.vibrate(pattern);
}

// ── Confetti burst (legendary) ──
function launchConfetti() {
  const canvas = document.createElement('canvas');
  canvas.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:10000';
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  document.body.appendChild(canvas);

  const ctx = canvas.getContext('2d');
  const colors = ['#ff8c00', '#ffd700', '#ff4500', '#fff4a3', '#ffb347', '#ffffff', '#ff6347'];
  const cx = canvas.width / 2;
  const cy = canvas.height * 0.35;
  const isMobile = window.innerWidth < 768;

  const particles = Array.from({length: isMobile ? 45 : 90}, () => {
    const angle = (Math.random() * Math.PI * 2);
    const speed = Math.random() * 7 + 3;
    return {
      x: cx + (Math.random() - 0.5) * 40,
      y: cy + (Math.random() - 0.5) * 20,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed - 4,
      color: colors[Math.floor(Math.random() * colors.length)],
      w: Math.random() * 8 + 4,
      h: Math.random() * 4 + 3,
      rot: Math.random() * 360,
      rotV: (Math.random() - 0.5) * 12,
      opacity: 1
    };
  });

  let frame = 0;
  const totalFrames = isMobile ? 70 : 100;

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    particles.forEach(p => {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.22;
      p.vx *= 0.99;
      p.rot += p.rotV;
      p.opacity = Math.max(0, 1 - frame / totalFrames);

      ctx.save();
      ctx.globalAlpha = p.opacity;
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot * Math.PI / 180);
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
      ctx.restore();
    });

    frame++;
    if (frame < totalFrames) requestAnimationFrame(draw);
    else canvas.remove();
  }

  requestAnimationFrame(draw);
}

// ── Toasts: legendary finds by others, collection updates ──
function showToast(text) {
  let box = document.getElementById('scav-toasts');
  if (!box) {
    box = document.createElement('div');
    box.id = 'scav-toasts';
    box.setAttribute('role', 'status');
    document.body.appendChild(box);
  }
  // a burst of finds shouldn't bury the page
  while (box.children.length >= 3) box.firstElementChild.remove();
  const toast = document.createElement('div');
  toast.className = 'scav-toast';
  toast.textContent = text;
  box.appendChild(toast);
  setTimeout(() => toast.classList.add('scav-toast-hide'), 4500);
  setTimeout(() => toast.remove(), 5000);
}

window.addEventListener('phx:legendary-found', (e) => showToast(e.detail.text));

// ── Legendary collection: kept per browser, shown on /collection ──
const COLLECTION_KEY = 'scavgen:legendaries';

function loadCollection() {
  try { return JSON.parse(localStorage.getItem(COLLECTION_KEY)) || []; } catch { return []; }
}

function collectLegendary(name, toastText) {
  const found = loadCollection();
  if (found.includes(name)) return;
  found.push(name);
  try { localStorage.setItem(COLLECTION_KEY, JSON.stringify(found)); } catch { return; }
  showToast(toastText);
}

const CollectionHook = {
  mounted() { this.pushEvent('load_collection', {names: loadCollection()}); },
  reconnected() { this.mounted(); }
};

// ── Wheel spin music: played inside the click so mobile autoplay rules allow it ──
window.addEventListener('wheel:play', (e) => {
  e.target.currentTime = 0;
  e.target.play().catch(() => {});
});

// Clip is as long as the longest spin, so shorter spins fade it out on reveal.
// Step counter, not volume check: iOS ignores audio.volume writes.
window.addEventListener('wheel:stop', (e) => {
  const audio = e.target;
  let step = 10;
  const fade = setInterval(() => {
    audio.volume = --step / 10;
    if (step === 0) { clearInterval(fade); audio.pause(); audio.volume = 1; }
  }, 40);
});

// ── Bring the result into view (check page suggestions sit below it) ──
window.addEventListener('scav:reveal', (e) => {
  e.target.scrollIntoView({behavior: 'smooth', block: 'center'});
});

// ── Shortcuts modal toggle (exposed on window for inline onclick) ──
window.toggleShortcutsModal = function() {
  const modal = document.getElementById('shortcuts-modal');
  if (modal) modal.classList.toggle('hidden');
};

function makeTurnstileHook() {
  const callbackEvent = (self, name, eventName) => {
    return (payload) => {
      const events = self.el.dataset.events || ""
      if (events.split(",").indexOf(name) > -1) {
        self.pushEventTo(self.el, `turnstile:${eventName || name}`, payload)
      }
    }
  }

  return {
    mounted() {
      const buttonId = this.el.dataset.buttonId
      const setButton = (disabled) => {
        if (buttonId) {
          const btn = document.getElementById(buttonId)
          if (btn) btn.disabled = disabled
        }
      }

      turnstile.render(this.el, {
        callback: (token) => { callbackEvent(this, "success")(token); setButton(false) },
        "error-callback": (code) => { callbackEvent(this, "error")(code); setButton(true) },
        "expired-callback": () => { callbackEvent(this, "expired")({}); setButton(true) },
        "before-interactive-callback": callbackEvent(this, "beforeInteractive", "before-interactive"),
        "after-interactive-callback": callbackEvent(this, "afterInteractive", "after-interactive"),
        "unsupported-callback": callbackEvent(this, "unsupported"),
        "timeout-callback": callbackEvent(this, "timeout")
      })

      this.handleEvent("turnstile:refresh", (event) => {
        if (!event.id || event.id === this.el.id) {
          setButton(true)
          turnstile.reset(this.el)
        }
      })

      this.handleEvent("turnstile:remove", (event) => {
        if (!event.id || event.id === this.el.id) {
          turnstile.remove(this.el)
        }
      })
    }
  }
}

const ScavNameHook = {
  mounted() { this.reveal() },
  updated() { this.reveal() },
  reveal() {
    const el = this.el;
    el.classList.remove(
      'scav-appear', 'gnome-appear', 'neuro-appear', 'queue-appear', 'error-appear',
      'legendary-appear', 'epic-appear', 'rare-appear'
    );
    void el.offsetWidth;
    if (el.closest('.gnome-name, .team-gnome-name')) {
      el.classList.add('gnome-appear');
      vibrate([50, 30, 50, 30, 50]);
    } else if (el.closest('.neuro-name')) {
      el.classList.add('neuro-appear');
      vibrate(20);
    } else if (el.closest('.queue-name')) {
      el.classList.add('queue-appear');
    } else if (el.closest('.error-name')) {
      el.classList.add('error-appear');
    } else if (el.closest('.legendary-name, .team-legendary-name')) {
      el.classList.add('legendary-appear');
      // only generated names count, not checked ones (data-collect holds the toast text)
      if (el.dataset.collect) collectLegendary(el.textContent.trim(), el.dataset.collect);
      triggerRarityFlash('legendary');
      launchConfetti();
      vibrate([100, 50, 100, 50, 200]);
    } else if (el.closest('.epic-name, .team-epic-name')) {
      el.classList.add('epic-appear');
      triggerRarityFlash('epic');
      triggerScreenShake();
      vibrate([70, 30, 70]);
    } else if (el.closest('.rare-name, .team-rare-name')) {
      el.classList.add('rare-appear');
      vibrate(30);
    } else {
      el.classList.add('scav-appear');
      vibrate(15);
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    Turnstile: makeTurnstileHook(),
    ScavName: ScavNameHook,
    Collection: CollectionHook
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// ── Service Worker (PWA) ──
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  });
}

// ── Close page/lang dropdowns on outside click ──
document.addEventListener('click', (e) => {
  document.querySelectorAll('details.lang-dropdown[open]').forEach((d) => {
    if (!d.contains(e.target)) d.open = false;
  });
});

// ── Keyboard shortcuts ──
document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) return;
  if (e.ctrlKey || e.altKey || e.metaKey) return;

  if (e.key === ' ') {
    e.preventDefault();
    const btn = document.getElementById('btn-single') ||
                document.getElementById('btn-team') ||
                document.getElementById('neuroButton') ||
                document.getElementById('btn-wheel');
    if (btn && !btn.disabled) btn.click();
  } else if (e.key === '1') {
    window.location.href = '/';
  } else if (e.key === '2') {
    window.location.href = '/team_scavengers';
  } else if (e.key === '3') {
    window.location.href = '/neuro_scavengers';
  } else if (e.key === '4') {
    window.location.href = '/statistics';
  } else if (e.key === '5') {
    window.location.href = '/wheel';
  } else if (e.key === '6') {
    window.location.href = '/check_name';
  } else if (e.key === '7') {
    window.location.href = '/collection';
  } else if (e.key === '?') {
    window.toggleShortcutsModal();
  } else if (e.key === 'Escape') {
    const modal = document.getElementById('shortcuts-modal');
    if (modal && !modal.classList.contains('hidden')) modal.classList.add('hidden');
  }
});
