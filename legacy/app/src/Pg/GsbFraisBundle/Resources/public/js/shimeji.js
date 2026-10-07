/* Shimeji, pour une blague : à retirer (voir layout.html.twig).
   Un castor et un capybara se promènent en bas de l'écran. De temps en temps,
   l'un d'eux saute sur la souris et file vers le bord avec, comme Desktop Goose.
   Une page ne peut pas déplacer le vrai curseur : il est masqué, un faux part
   dans la gueule de l'animal, et aucun clic n'atteint la page pendant le vol.
   Secouer la souris lui fait lâcher prise ; on peut aussi attraper les animaux
   et les lancer. Ils n'arrivent qu'une fois le faux captcha passé. */
(function () {
  if (!window.requestAnimationFrame || !window.matchMedia) return;

  // Le vol n'a de sens qu'avec une vraie souris ; au doigt, ils se promènent.
  var SOURIS = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  var GRAVITE = 2400;     // px/s²
  var SECOUSSE = 2500;    // mouvement de souris (px) qui fait lâcher prise
  var html = document.documentElement;

  // Dessins tournés vers la droite, pattes en bas (viewBox 80 × 56).
  // « gueule » : où tenir le curseur, depuis le milieu des pattes, pour 80 px de large.
  var ESPECES = {
    capybara: {
      marche: 55, course: 330, gueule: [35, -26], premierVol: [5000, 9000],
      svg: '<svg viewBox="0 0 80 56" aria-hidden="true">'
        + '<g class="patte-b" fill="#7E5530"><rect x="22" y="41" width="6" height="13" rx="2.5"/><rect x="45" y="41" width="6" height="13" rx="2.5"/></g>'
        + '<ellipse cx="36" cy="33" rx="26" ry="15" fill="#B07A45" stroke="#6E4A26" stroke-width="2"/>'
        + '<ellipse cx="53" cy="15" rx="4" ry="3" fill="#8C5C30" stroke="#6E4A26" stroke-width="1.5"/>'
        + '<rect x="47" y="14" width="29" height="23" rx="10" fill="#B07A45" stroke="#6E4A26" stroke-width="2"/>'
        + '<circle class="oeil" cx="62" cy="22" r="2" fill="#2B1B0E"/>'
        + '<ellipse cx="73.5" cy="24" rx="1.6" ry="2.2" fill="#2B1B0E"/>'
        + '<path d="M68 31q3 2 6 0" fill="none" stroke="#6E4A26" stroke-width="1.5" stroke-linecap="round"/>'
        + '<g class="patte-a" fill="#8C5C30"><rect x="14" y="41" width="6" height="13" rx="2.5"/><rect x="52" y="41" width="6" height="13" rx="2.5"/></g>'
        // Le yuzu sur la tête, comme il se doit.
        + '<circle cx="60" cy="9" r="5" fill="#F2A33A" stroke="#B86E14" stroke-width="1.2"/>'
        + '<path d="M60 4q2-3 5-2-1 3-5 2z" fill="#5E9C3A"/>'
        + '</svg>'
    },
    castor: {
      marche: 85, course: 400, gueule: [30, -22], premierVol: [11000, 16000],
      svg: '<svg viewBox="0 0 80 56" aria-hidden="true">'
        // La queue plate, quadrillée, derrière.
        + '<g transform="rotate(-18 14 40)"><ellipse cx="12" cy="40" rx="12" ry="6" fill="#4A3322" stroke="#2E1F14" stroke-width="1.5"/>'
        + '<path d="M4 38h16M4 42h16M8 35v10M12 34v12M16 35v10" stroke="#2E1F14" stroke-width=".8" opacity=".6"/></g>'
        + '<g class="patte-b" fill="#4E3019"><rect x="26" y="42" width="6" height="12" rx="2.5"/><rect x="44" y="42" width="6" height="12" rx="2.5"/></g>'
        + '<ellipse cx="38" cy="34" rx="22" ry="15" fill="#7A4E2D" stroke="#4A2E18" stroke-width="2"/>'
        + '<ellipse cx="45" cy="38" rx="11" ry="9" fill="#A8754A"/>'
        + '<circle cx="51" cy="12" r="3.5" fill="#5E3B20" stroke="#4A2E18" stroke-width="1.5"/>'
        + '<circle cx="59" cy="23" r="13" fill="#7A4E2D" stroke="#4A2E18" stroke-width="2"/>'
        + '<ellipse cx="69" cy="27" rx="7" ry="5.5" fill="#A8754A" stroke="#4A2E18" stroke-width="1.5"/>'
        + '<ellipse cx="74" cy="24.5" rx="2.6" ry="2" fill="#1E120A"/>'
        + '<circle class="oeil" cx="62" cy="19" r="2" fill="#1E120A"/>'
        // Les deux grandes dents.
        + '<path d="M66 32h6v6.5a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1z" fill="#FFF4D6" stroke="#B89A5E" stroke-width="1"/>'
        + '<path d="M69 32v7.5" stroke="#B89A5E" stroke-width="1"/>'
        + '<g class="patte-a" fill="#5E3B20"><rect x="19" y="42" width="6" height="12" rx="2.5"/><rect x="51" y="42" width="6" height="12" rx="2.5"/></g>'
        + '</svg>'
    }
  };

  function entre(a, b) { return a + Math.random() * (b - a); }
  function maintenant() { return window.performance.now(); }

  // --- la souris ---

  var souris = { x: 0, y: 0, dedans: false, traces: [] };
  var voleur = null;      // l'animal qui tient la souris
  var chasseur = null;    // l'animal qui lui court après (un seul à la fois)
  var secousse = 0;

  document.addEventListener('pointermove', function (e) {
    if (voleur && e.pointerType === 'mouse') secousse += Math.abs(e.movementX) + Math.abs(e.movementY);
    souris.x = e.clientX;
    souris.y = e.clientY;
    if (e.pointerType === 'mouse') souris.dedans = true;
    souris.traces.push({ x: e.clientX, y: e.clientY, t: e.timeStamp });
    while (souris.traces.length > 2 && e.timeStamp - souris.traces[0].t > 100) souris.traces.shift();
  }, true);
  html.addEventListener('mouseleave', function () {
    souris.dedans = false;
    lache();
  });
  window.addEventListener('blur', lache);

  // Vitesse de la main au lâcher : un animal lâché en plein geste est lancé,
  // à 2 500 px/s au plus pour qu'un geste brusque ne l'expédie pas trop loin.
  function elan() {
    var t = souris.traces;
    if (t.length < 2) return [0, 0];
    var a = t[0], b = t[t.length - 1], duree = (b.t - a.t) / 1000;
    if (duree <= 0) return [0, 0];
    var borne = function (v) { return Math.max(-2500, Math.min(2500, v)); };
    return [borne((b.x - a.x) / duree), borne((b.y - a.y) / duree)];
  }

  // --- le vol : faux curseur, et bouclier contre les clics ---

  var scene = document.createElement('div');
  scene.className = 'shimeji-scene';
  var bouclier = document.createElement('div');
  bouclier.className = 'shimeji-bouclier';
  bouclier.hidden = true;
  ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'dblclick', 'contextmenu'].forEach(function (type) {
    bouclier.addEventListener(type, function (e) {
      e.preventDefault();
      e.stopPropagation();
    });
  });
  var curseur = document.createElement('div');
  curseur.className = 'shimeji-curseur';
  curseur.hidden = true;
  curseur.innerHTML = '<svg viewBox="0 0 12 18" aria-hidden="true"><path d="M1 1v13.5l3.3-3.2 2.3 5.3 2.1-.9-2.3-5.2H11z"'
    + ' fill="#FFFFFF" stroke="#000000" stroke-width="1" stroke-linejoin="round"/></svg>';

  function placeCurseur(x, y, angle) {
    curseur.style.transform = 'translate(' + (x - 1.5) + 'px, ' + (y - 1.5) + 'px) rotate(' + angle + 'deg)';
  }

  function vole(b) {
    voleur = b;
    chasseur = null;
    secousse = 0;
    html.classList.add('shimeji-vol');
    bouclier.hidden = false;
    curseur.classList.remove('shimeji-curseur--retour');
    curseur.hidden = false;
    b.etat = 'vol';
    b.debutVol = maintenant();
    b.auBord = 0;
    // Il file vers le bord le plus proche.
    b.sens = b.x < window.innerWidth / 2 ? -1 : 1;
  }

  function lache() {
    var b = voleur;
    if (!b) return;
    voleur = null;
    // Le faux curseur rejoint le vrai, puis le vrai réapparaît.
    curseur.classList.add('shimeji-curseur--retour');
    placeCurseur(souris.x, souris.y, 0);
    setTimeout(function () {
      if (voleur) return;   // un nouveau vol a déjà commencé
      curseur.hidden = true;
      curseur.classList.remove('shimeji-curseur--retour');
      html.classList.remove('shimeji-vol');
      bouclier.hidden = true;
    }, 260);
    b.etat = 'chute';
    b.vx = 0;
    b.prochainVol = maintenant() + entre(12000, 22000);
  }

  // --- les animaux ---

  function Bestiole(espece, depuisLaGauche) {
    var b = this;
    this.espece = espece;
    this.e = ESPECES[espece];
    this.el = document.createElement('div');
    // La classe d'abord : c'est elle qui donne la taille que mesure() relève.
    this.el.className = this.classe = 'shimeji shimeji--' + espece;
    this.el.setAttribute('aria-hidden', 'true');
    this.el.innerHTML = '<div class="shimeji__sens"><div class="shimeji__pose">' + this.e.svg + '</div></div>';
    // Ils arrivent du bord de l'écran.
    this.x = depuisLaGauche ? -60 : window.innerWidth + 60;
    this.y = window.innerHeight;
    this.vx = 0;
    this.vy = 0;
    this.sens = depuisLaGauche ? 1 : -1;
    this.etat = 'marche';
    this.minuteur = entre(4, 7);
    this.prochainVol = maintenant() + entre(this.e.premierVol[0], this.e.premierVol[1]);

    // Attrapé à la souris ou au doigt : il pend, puis tombe ou s'envole au lâcher.
    this.el.addEventListener('pointerdown', function (e) {
      if (b === voleur) return;
      e.preventDefault();
      b.el.setPointerCapture(e.pointerId);
      if (chasseur === b) chasseur = null;
      b.etat = 'tenu';
    });
    function relache() {
      if (b.etat !== 'tenu') return;
      var v = elan();
      b.vx = v[0];
      b.vy = v[1];
      b.etat = 'chute';
    }
    this.el.addEventListener('pointerup', relache);
    this.el.addEventListener('pointercancel', relache);

    scene.appendChild(this.el);
    this.mesure();
  }

  Bestiole.prototype.mesure = function () {
    this.l = this.el.offsetWidth;
    this.h = this.el.offsetHeight;
  };

  Bestiole.prototype.gueule = function () {
    var k = this.l / 80;
    return [this.x + this.sens * this.e.gueule[0] * k, this.y + this.e.gueule[1] * k];
  };

  Bestiole.prototype.peutVoler = function (t) {
    return SOURIS && souris.dedans && !voleur && !chasseur && t > this.prochainVol;
  };

  Bestiole.prototype.abandonne = function (t, delai) {
    if (chasseur === this) chasseur = null;
    this.etat = 'repos';
    this.minuteur = entre(1, 2);
    this.vx = this.vy = 0;
    this.prochainVol = t + delai;
  };

  // Saut calculé pour que la gueule passe par la souris.
  Bestiole.prototype.saute = function () {
    var k = this.l / 80;
    var cx = souris.x - this.sens * this.e.gueule[0] * k;
    var cy = Math.min(window.innerHeight, souris.y - this.e.gueule[1] * k);
    var dx = cx - this.x, dy = cy - this.y;
    var duree = 0.5 + Math.min(0.35, Math.abs(dy) / 2000);
    this.vx = dx / duree;
    this.vy = (dy - 0.5 * GRAVITE * duree * duree) / duree;
    this.etat = 'saut';
  };

  Bestiole.prototype.avance = function (dt, t) {
    var largeur = window.innerWidth, sol = window.innerHeight, demi = this.l / 2, e = this.e, g;
    switch (this.etat) {
      case 'repos':
        this.y = sol;
        this.minuteur -= dt;
        if (this.peutVoler(t)) this.chasse(t);
        else if (this.minuteur <= 0) {
          this.etat = 'marche';
          this.sens = Math.random() < 0.5 ? -1 : 1;
          this.minuteur = entre(2, 5);
        }
        break;

      case 'marche':
        this.y = sol;
        this.x += this.sens * e.marche * dt;
        // Demi-tour au bord ; en arrivant de l'extérieur, il continue d'entrer.
        if (this.x < demi && this.sens < 0) this.sens = 1;
        if (this.x > largeur - demi && this.sens > 0) this.sens = -1;
        this.minuteur -= dt;
        if (this.peutVoler(t)) this.chasse(t);
        else if (this.minuteur <= 0) {
          this.etat = 'repos';
          this.minuteur = entre(1, 3);
        }
        break;

      case 'chasse':
        this.y = sol;
        if (!souris.dedans || voleur || t > this.finChasse) {
          this.abandonne(t, 8000);
          break;
        }
        var ecart = souris.x - this.x;
        this.sens = ecart < 0 ? -1 : 1;
        this.x += this.sens * Math.min(Math.abs(ecart), e.course * dt);
        if (Math.abs(ecart) < 240) this.saute();
        break;

      case 'saut':
      case 'chute':
        this.vy += GRAVITE * dt;
        this.x += this.vx * dt;
        this.y += this.vy * dt;
        // Rebonds sur les côtés de la fenêtre, arrêt au plafond.
        if (this.x < demi) { this.x = demi; this.vx = Math.abs(this.vx) * 0.4; }
        if (this.x > largeur - demi) { this.x = largeur - demi; this.vx = -Math.abs(this.vx) * 0.4; }
        if (this.y < this.h && this.vy < 0) { this.y = this.h; this.vy = 0; }
        if (Math.abs(this.vx) > 30) this.sens = this.vx < 0 ? -1 : 1;
        if (this.etat === 'saut' && !voleur && souris.dedans) {
          g = this.gueule();
          if (Math.abs(g[0] - souris.x) < 34 && Math.abs(g[1] - souris.y) < 34) {
            vole(this);
            break;
          }
        }
        if (this.y >= sol) {
          this.y = sol;
          if (this.etat === 'chute' && this.vy > 700) {
            this.vy = -this.vy * 0.3;
            this.vx *= 0.6;
          } else if (this.etat === 'saut') {
            this.abandonne(t, entre(4000, 8000));   // raté : il retentera bientôt
          } else {
            this.etat = 'repos';
            this.minuteur = entre(0.8, 1.5);
            this.vx = this.vy = 0;
          }
        }
        break;

      case 'vol':
        if (this.y < sol) {
          // Il retombe avec la souris, puis court vers le bord.
          this.vy += GRAVITE * dt;
          this.y = Math.max(this.h, Math.min(sol, this.y + this.vy * dt));
        } else {
          this.x += this.sens * e.course * 1.15 * dt;
          if (this.x <= demi || this.x >= largeur - demi) {
            this.x = Math.max(demi, Math.min(largeur - demi, this.x));
            this.auBord += dt;
          }
        }
        g = this.gueule();
        placeCurseur(g[0], g[1], this.sens * -35);
        if (secousse > SECOUSSE || this.auBord > 0.9 || t - this.debutVol > 7000) lache();
        break;

      case 'tenu':
        // Tenu par la peau du cou, juste sous le curseur.
        this.x = souris.x;
        this.y = souris.y + this.h * 0.8;
        this.vx = this.vy = 0;
        break;
    }
  };

  Bestiole.prototype.chasse = function (t) {
    chasseur = this;
    this.etat = 'chasse';
    this.finChasse = t + 6000;
  };

  var POSES = { repos: 'repos', marche: 'marche', chasse: 'course', saut: 'saut', chute: 'saut', vol: 'course', tenu: 'tenu' };

  Bestiole.prototype.dessine = function () {
    var pose = this.etat === 'vol' && this.y < window.innerHeight ? 'saut' : POSES[this.etat];
    var classe = 'shimeji shimeji--' + this.espece + ' shimeji--' + pose + (this.sens < 0 ? ' shimeji--gauche' : '');
    if (classe !== this.classe) {
      this.el.className = classe;
      this.classe = classe;
    }
    this.el.style.transform = 'translate3d(' + Math.round(this.x - this.l / 2) + 'px, ' + Math.round(this.y - this.h) + 'px, 0)';
  };

  // --- la boucle ---

  var bestioles = [];
  var avant = 0;
  function boucle(t) {
    var dt = Math.min(0.05, (t - avant) / 1000);   // onglet en arrière-plan : pas de bond
    avant = t;
    for (var i = 0; i < bestioles.length; i++) {
      bestioles[i].avance(dt, t);
      bestioles[i].dessine();
    }
    window.requestAnimationFrame(boucle);
  }

  function demarre() {
    document.body.appendChild(scene);
    document.body.appendChild(bouclier);
    document.body.appendChild(curseur);
    bestioles.push(new Bestiole('capybara', true), new Bestiole('castor', false));
    window.addEventListener('resize', function () {
      for (var i = 0; i < bestioles.length; i++) bestioles[i].mesure();
    });
    window.requestAnimationFrame(function (t) {
      avant = t;
      window.requestAnimationFrame(boucle);
    });
  }

  // Le faux captcha d'abord, s'il est là : ils arrivent quand il disparaît.
  if (document.querySelector('.faux-captcha')) {
    var guet = new MutationObserver(function () {
      if (document.querySelector('.faux-captcha')) return;
      guet.disconnect();
      demarre();
    });
    guet.observe(document.body, { childList: true });
  } else {
    demarre();
  }
})();
