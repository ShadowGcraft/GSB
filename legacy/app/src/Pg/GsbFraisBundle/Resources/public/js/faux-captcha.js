/* Faux captcha, pour une blague : à retirer (voir layout.html.twig).
   Ce n'est pas une vraie vérification : rien n'est envoyé au serveur, et sans
   JavaScript la page reste utilisable. À chaque page, un bouton « Je ne suis pas
   un robot » colle à la souris et bloque la page jusqu'à l'épreuve d'images,
   dont le premier essai échoue toujours. */
(function () {
  // Navigateur trop ancien : pas de blague, plutôt qu'une page bloquée pour de bon.
  if (!window.HTMLDialogElement || !('inert' in HTMLElement.prototype)) return;

  // Ce qu'il faut trouver, parmi les icônes de l'appli (_icones.html.twig).
  var SUJETS = [
    { id: 'TRA', nom: 'un train' }, { id: 'AVI', nom: 'un avion' },
    { id: 'TAX', nom: 'une voiture' }, { id: 'VEL', nom: 'un vélo' },
    { id: 'TEL', nom: 'un téléphone' }, { id: 'IMP', nom: 'une imprimante' },
    { id: 'POS', nom: 'une enveloppe' }, { id: 'INF', nom: 'un ordinateur' }
  ];
  // Les autres images : ni voiture ni train, pour qu'aucune ne prête à confusion.
  var LEURRES = ['DIN', 'PDJ', 'INV', 'COL', 'SAL', 'TRT', 'FAN', 'FLE', 'CON',
                 'FOU', 'FOR', 'DOC', 'PRE', 'BAN', 'PAR', 'REP', 'NUI', 'ETP'];
  // Fonds des « photos ».
  var FONDS = ['#5B7F95', '#7A8B5C', '#9C6B4E', '#6E6A8F', '#4F8A83', '#8F5F6E', '#A08A4E', '#5E7A6B'];

  function hasard(n) { return Math.floor(Math.random() * n); }
  function melange(t) {
    for (var i = t.length - 1; i > 0; i--) {
      var j = hasard(i + 1), x = t[i];
      t[i] = t[j];
      t[j] = x;
    }
    return t;
  }
  function trait(chemins, epaisseur) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + epaisseur
         + '" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + chemins + '</svg>';
  }

  var racine = document.createElement('div');
  racine.className = 'faux-captcha';
  racine.innerHTML =
    '<button type="button" class="faux-captcha__bouton">'
    + '<span class="faux-captcha__case">' + trait('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 3) + '</span>'
    + '<span class="faux-captcha__libelle">Je ne suis pas un robot</span>'
    + '<span class="faux-captcha__marque" aria-hidden="true">'
    + trait('<path d="M12 3l7 3v5c0 4.5-3 8.3-7 10-4-1.7-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/>', 2)
    + 'Vérification<br>GSB</span>'
    + '</button>'
    + '<dialog class="faux-captcha__epreuve" aria-labelledby="fauxCaptchaConsigne">'
    + '<p class="faux-captcha__consigne" id="fauxCaptchaConsigne"></p>'
    + '<div class="faux-captcha__grille"></div>'
    + '<p class="faux-captcha__erreur" role="alert"></p>'
    + '<div class="faux-captcha__pied">'
    + '<button type="button" class="faux-captcha__recharger" title="Nouvelles images" aria-label="Nouvelles images">'
    + trait('<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>', 2) + '</button>'
    + '<button type="button" class="faux-captcha__verifier">Vérifier</button>'
    + '</div>'
    + '</dialog>';

  var bouton = racine.querySelector('.faux-captcha__bouton');
  var epreuve = racine.querySelector('.faux-captcha__epreuve');
  var consigne = racine.querySelector('.faux-captcha__consigne');
  var grille = racine.querySelector('.faux-captcha__grille');
  var erreur = racine.querySelector('.faux-captcha__erreur');
  var cibles = [];      // les cases où se trouve le sujet
  var essais = 0;       // essais avec au moins une image cochée
  var verifie = false;

  function nouvelleGrille() {
    var sujet = SUJETS[hasard(SUJETS.length)];
    var autres = LEURRES.slice();
    for (var s = 0; s < SUJETS.length; s++) {
      if (SUJETS[s] !== sujet) autres.push(SUJETS[s].id);
    }
    melange(autres);
    var nbCibles = 3 + hasard(2);
    var cases = [];
    for (var i = 0; i < 9; i++) cases.push(i < nbCibles ? sujet.id : autres[i]);
    melange(cases);

    consigne.innerHTML = 'Sélectionnez toutes les images avec <strong>' + sujet.nom + '</strong>'
      + 'Cliquez sur Vérifier une fois terminé.';
    grille.innerHTML = '';
    cibles = [];
    for (var k = 0; k < cases.length; k++) {
      var tuile = document.createElement('button');
      tuile.type = 'button';
      tuile.className = 'faux-captcha__tuile';
      tuile.setAttribute('aria-pressed', 'false');
      tuile.setAttribute('aria-label', 'Image ' + (k + 1));
      tuile.innerHTML = '<span class="faux-captcha__image" style="background:' + FONDS[hasard(FONDS.length)] + '">'
        + '<svg aria-hidden="true" style="transform: rotate(' + (hasard(51) - 25) + 'deg) scale(' + (0.8 + hasard(36) / 100) + ')">'
        + '<use href="#ic-' + cases[k] + '"/></svg></span>';
      grille.appendChild(tuile);
      if (cases[k] === sujet.id) cibles.push(k);
    }
    erreur.textContent = '';
  }

  function ouvre() {
    if (verifie || epreuve.open) return;
    nouvelleGrille();
    epreuve.showModal();
  }

  function reussite() {
    verifie = true;
    epreuve.close();
    racine.classList.add('faux-captcha--verifie');
    bouton.querySelector('.faux-captcha__libelle').textContent = 'Vérifié : vous êtes humain';
    setTimeout(function () {
      racine.classList.add('faux-captcha--parti');
      setTimeout(libere, 300);
    }, 900);
  }

  // La page reprend la main : plus de voile, plus de bouton.
  function libere() {
    for (var i = 0; i < bloques.length; i++) bloques[i].inert = false;
    document.removeEventListener('pointermove', suit);
    racine.parentNode.removeChild(racine);
  }

  grille.addEventListener('click', function (e) {
    var tuile = e.target.closest('.faux-captcha__tuile');
    if (!tuile) return;
    tuile.setAttribute('aria-pressed', String(tuile.getAttribute('aria-pressed') !== 'true'));
    erreur.textContent = '';
  });
  racine.querySelector('.faux-captcha__recharger').addEventListener('click', nouvelleGrille);
  racine.querySelector('.faux-captcha__verifier').addEventListener('click', function () {
    var tuiles = grille.querySelectorAll('.faux-captcha__tuile'), choisies = [];
    for (var i = 0; i < tuiles.length; i++) {
      if (tuiles[i].getAttribute('aria-pressed') === 'true') choisies.push(i);
    }
    if (!choisies.length) {
      erreur.textContent = 'Veuillez sélectionner toutes les images correspondantes.';
      return;
    }
    essais++;
    // Le piège : le premier essai échoue toujours, même juste.
    if (essais > 1 && choisies.join() === cibles.join()) {
      reussite();
      return;
    }
    nouvelleGrille();
    erreur.textContent = 'Veuillez réessayer.';
  });

  // Un clic n'importe où sur le voile, ou sur le bouton, ouvre l'épreuve.
  racine.addEventListener('click', function (e) {
    if (!epreuve.contains(e.target)) ouvre();
  });

  // Le bouton colle à la souris. Au doigt, il reste au milieu de l'écran.
  function place(x, y) {
    bouton.style.transform = 'translate(' + Math.round(x - bouton.offsetWidth / 2) + 'px, '
                            + Math.round(y - bouton.offsetHeight / 2) + 'px)';
  }
  function suit(e) {
    if (e.pointerType !== 'touch' && !epreuve.open && !verifie) place(e.clientX, e.clientY);
  }

  // Tout le reste de la page est bloqué (ni clic ni clavier) jusqu'à la vérification.
  var bloques = [];
  for (var i = 0; i < document.body.children.length; i++) {
    var el = document.body.children[i];
    if (!el.inert) {
      el.inert = true;
      bloques.push(el);
    }
  }
  document.body.appendChild(racine);
  place(window.innerWidth / 2, window.innerHeight / 2);
  document.addEventListener('pointermove', suit);
  bouton.focus({ preventScroll: true });
})();
