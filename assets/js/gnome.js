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
        }, 10000);
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