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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
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


class GnomeFooter {
    constructor() {
        this.footer = document.getElementById('gnomeFooter');
        this.gnomeImage = document.getElementById('gnomeImage');
        this.isVisible = false;
        this.timeoutId = null;
        this.leftInterval = [1, 2, 3, 4, 5, 6, 7];
        this.rightInterval = [10_000, 15_000, 40_000, 45_000, 50_000, 60_000, 90_000];
        
        this.gnomeSound = new Audio();
        this.gnomeSound.src = '/sounds/gnome_sound.mp3';
        
        this.init();
    }

    init() {
        this.gnomeImage.addEventListener('click', () => this.onGnomeClick());
        
        this.scheduleNextAppearance();
    }

    scheduleNextAppearance() {
        // const randomTime = Math.round(Math.random() * 20000 + 10000);
        const initialNumber =  this.leftInterval[Math.floor((Math.random()*this.leftInterval.length))];
        const coefficient = this.rightInterval[Math.floor((Math.random()*this.rightInterval.length))];
        const randomTime = initialNumber * coefficient;
        
        this.timeoutId = setTimeout(() => {
            if (!this.isVisible) {
                this.showFooter();
            }
        }, randomTime);
    }

    showFooter() {
        this.footer.classList.add('show');
        this.footer.classList.remove('hide');
        this.isVisible = true;
        
        setTimeout(() => {
            if (this.isVisible) {
                this.hideFooter();
            }
        }, 5000);
    }

    hideFooter() {
        this.footer.classList.add('hide');
        this.footer.classList.remove('show');
        this.isVisible = false;
        
        // Планируем следующее появление
        setTimeout(() => {
            this.scheduleNextAppearance();
        }, 2000);
    }

    onGnomeClick() {
        // Воспроизводим звук
        this.playGnomeSound();
        
        // Добавляем анимацию прыжка гнома
        this.gnomeImage.classList.add('clicked');
        
        // Убираем класс анимации через время её выполнения
        setTimeout(() => {
            this.gnomeImage.classList.remove('clicked');
        }, 600);
        
        // Скрываем футер с задержкой
        setTimeout(() => {
            this.hideFooter();
        }, 800);
    }

    playGnomeSound() {
        this.gnomeSound.play();
    }
}


document.addEventListener('DOMContentLoaded', () => {
    new GnomeFooter();
});