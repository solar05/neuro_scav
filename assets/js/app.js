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
    } else if (el.closest('.neuro-name')) {
      el.classList.add('neuro-appear');
    } else if (el.closest('.queue-name')) {
      el.classList.add('queue-appear');
    } else if (el.closest('.error-name')) {
      el.classList.add('error-appear');
    } else if (el.closest('.legendary-name, .team-legendary-name')) {
      el.classList.add('legendary-appear');
      triggerRarityFlash('legendary');
    } else if (el.closest('.epic-name, .team-epic-name')) {
      el.classList.add('epic-appear');
      triggerRarityFlash('epic');
    } else if (el.closest('.rare-name, .team-rare-name')) {
      el.classList.add('rare-appear');
    } else {
      el.classList.add('scav-appear');
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    Turnstile: makeTurnstileHook(),
    ScavName: ScavNameHook
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

// ── Keyboard shortcuts ──
document.addEventListener('keydown', (e) => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) return;
  if (e.ctrlKey || e.altKey || e.metaKey) return;

  if (e.key === ' ') {
    e.preventDefault();
    const btn = document.getElementById('btn-single') ||
                document.getElementById('btn-team') ||
                document.getElementById('neuroButton');
    if (btn && !btn.disabled) btn.click();
  } else if (e.key === '1') {
    window.location.href = '/single_scavenger';
  } else if (e.key === '2') {
    window.location.href = '/team_scavengers';
  } else if (e.key === '3') {
    window.location.href = '/neuro_scavengers';
  } else if (e.key === '4') {
    window.location.href = '/statistics';
  } else if (e.key === '?') {
    window.toggleShortcutsModal();
  } else if (e.key === 'Escape') {
    const modal = document.getElementById('shortcuts-modal');
    if (modal && !modal.classList.contains('hidden')) modal.classList.add('hidden');
  }
});
