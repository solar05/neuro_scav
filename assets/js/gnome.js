const LEFT_INTERVAL = [1, 2, 3, 4, 5, 6, 7];
const RIGHT_INTERVAL = [10_000, 15_000, 40_000, 45_000, 50_000, 60_000, 90_000];

class GnomeFooter {
    constructor() {
        this.footer = document.getElementById('gnomeFooter');
        this.gnomeImage = document.getElementById('gnomeImage');
        this.isVisible = false;
        this.timeoutId = null;
        this.autoHideId = null;

        this.gnomeSound = new Audio();
        this.gnomeSound.src = '/sounds/gnome_sound.mp3';
        this.gnomeSound.preload = 'auto';

        this.init();
    }

    init() {
        this.gnomeImage.addEventListener('click', () => this.onGnomeClick());

        this.scheduleNextAppearance();
    }

    scheduleNextAppearance() {
        clearTimeout(this.timeoutId);

        const initialNumber = LEFT_INTERVAL[Math.floor(Math.random() * LEFT_INTERVAL.length)];
        const coefficient = RIGHT_INTERVAL[Math.floor(Math.random() * RIGHT_INTERVAL.length)];
        const randomTime = 1;

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

        this.autoHideId = setTimeout(() => {
            if (this.isVisible) {
                this.hideFooter();
            }
        }, 10000);
    }

    hideFooter() {
        this.footer.classList.add('hide');
        this.footer.classList.remove('show');
        this.isVisible = false;

        setTimeout(() => {
            this.scheduleNextAppearance();
        }, 2000);
    }

    onGnomeClick() {
        if (!this.isVisible) return;
        this.isVisible = false;
        clearTimeout(this.autoHideId);

        this.playGnomeSound();

        this.gnomeImage.classList.add('clicked');
        setTimeout(() => {
            this.gnomeImage.classList.remove('clicked');
        }, 600);

        setTimeout(() => {
            this.hideFooter();
        }, 800);
    }

    playGnomeSound() {
        this.gnomeSound.play().catch(() => {});
    }
}


document.addEventListener('DOMContentLoaded', () => {
    new GnomeFooter();
});
