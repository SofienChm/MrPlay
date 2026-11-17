// Small captions + PiP button bar drawn on top of YouTube's player.
(function () {
  if (location.hostname.indexOf('youtube.com') === -1) return;
  if (window.__mrControls) return;
  window.__mrControls = true;

  var BAR_ID = '__mrplay_player_controls';
  var ICONS = {
    cc: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round"><path d="M2 7a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2z"/><path d="M10 9.5a2 2 0 0 0-2.5 2.5A2 2 0 0 0 10 14.5"/><path d="M16 9.5a2 2 0 0 0-2.5 2.5 2 2 0 0 0 2.5 2.5"/></svg>',
    pip: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2"><rect x="2" y="4" width="20" height="16" rx="2"/><rect x="10" y="11" width="8" height="6"/></svg>'
  };

  function makeButton(action, title, icon) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.title = title;
    btn.setAttribute('aria-label', title);
    btn.innerHTML = icon;
    btn.style.cssText = 'width:34px;height:34px;border-radius:50%;border:none;background:rgba(0,0,0,0.55);display:flex;align-items:center;justify-content:center;cursor:pointer;margin:0;padding:0;pointer-events:auto;';
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (window.__mr) window.__mr.bridge('playerControl', { action: action });
    });
    return btn;
  }

  function ensureBar() {
    var player = document.querySelector('#movie_player');
    if (!player) return;
    var bar = document.getElementById(BAR_ID);
    if (bar && player.contains(bar)) return;
    if (bar) bar.remove();
    var pos = getComputedStyle(player).position;
    if (pos !== 'absolute' && pos !== 'relative' && pos !== 'fixed') player.style.position = 'relative';
    bar = document.createElement('div');
    bar.id = BAR_ID;
    bar.style.cssText = 'position:absolute;top:10px;left:10px;z-index:100;display:flex;gap:6px;pointer-events:none;';
    bar.appendChild(makeButton('toggleCaptions', 'Captions', ICONS.cc));
    bar.appendChild(makeButton('pip', 'Picture in picture', ICONS.pip));
    player.appendChild(bar);
  }

  var queued = false;
  new MutationObserver(function () {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; ensureBar(); });
  }).observe(document.documentElement, { childList: true, subtree: true });
  ensureBar();
})();
