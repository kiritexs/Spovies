// Universal video progress tracking + auto-resume.
//
// Hooks directly into the HTML5 <video> element's native events so watch
// progress is tracked for **every** plugin — not just those that emit
// their own postMessage events (like Provider A).
//
// Also handles auto-resume: if RESUME_TARGET > 0, the script seeks the
// <video> to that position as soon as the media metadata is loaded.
//
// IMPORTANT: this UserScript must be injected with forMainFrameOnly:false
// because streaming sites put their <video> inside cross-origin iframes.
//
// RESUME_TARGET is substituted from Dart via the __SPOVIES_RESUME_TARGET__
// placeholder at load time (see PlayerScripts.videoProgress).
(function() {
  if (window.__spoviesVideoTracker) return;
  window.__spoviesVideoTracker = true;

  var THROTTLE_MS = 3000;
  var lastSent = 0;
  var RESUME_TARGET = __SPOVIES_RESUME_TARGET__;

  // ── Auto-resume strategy ─────────────────────────────────────────────
  //
  // The previous implementation used a single module-scoped `seekDone`
  // flag. That broke when streaming sites prepended a pre-roll ad whose
  // duration was greater than RESUME_TARGET: the ad video became the
  // first one whose `RESUME_TARGET < video.duration` check passed, so
  // the ad got seeked to the user's resume position and `seekDone`
  // latched globally — the real content video that arrived after the ad
  // was never seeked.
  //
  // The fix is two-layered:
  //   1. Per-video first-seek guard (`__spoviesSeeked` property on the
  //      video element) — each video can be seeked at most once.
  //   2. Duration heuristic — only consider videos with duration >=
  //      MAIN_VIDEO_MIN_S as "real content". 60 s safely covers all
  //      movie / TV episode content and excludes virtually every pre-
  //      roll ad (typical ad lengths: 6 s, 15 s, 30 s; longer 60-90 s
  //      ads happen but are uncommon on streaming-host embeds).
  var MAIN_VIDEO_MIN_S = 60;
  var seekedAVideo = false; // we still only need to seek ONE main video

  function send(eventName, video) {
    if (!video || !video.duration || isNaN(video.duration)) return;
    var now = Date.now();
    if (eventName === 'timeupdate' && (now - lastSent) < THROTTLE_MS) return;
    lastSent = now;

    var progress = (video.currentTime / video.duration) * 100;
    var payload = JSON.stringify({
      type: 'PLAYER_EVENT',
      data: {
        event: eventName,
        currentTime: video.currentTime,
        duration: video.duration,
        progress: progress
      }
    });
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('spoviesEventBridge', payload);
    }
  }

  var patched = new WeakSet();

  function hookVideo(video) {
    if (patched.has(video)) return;
    patched.add(video);

    // --- progress tracking listeners ---
    ['timeupdate', 'play', 'pause', 'ended', 'seeked'].forEach(function(ev) {
      video.addEventListener(ev, function() { send(ev, video); });
    });

    // --- auto-resume seek ---
    if (RESUME_TARGET > 0) {
      function doSeek() {
        if (seekedAVideo || video.__spoviesSeeked) return;
        if (!video.duration || video.duration <= 0) return;
        // Skip short videos — they're pre-roll ads, not main content.
        if (video.duration < MAIN_VIDEO_MIN_S) return;
        // Can't seek past the end.
        if (RESUME_TARGET >= video.duration) return;
        video.__spoviesSeeked = true;
        seekedAVideo = true;
        video.currentTime = RESUME_TARGET;
      }
      // Try immediately if metadata already loaded.
      if (video.readyState >= 1) {
        doSeek();
      } else {
        video.addEventListener('loadedmetadata', doSeek, { once: true });
      }
      // Safety net: also try on canplay in case loadedmetadata already fired.
      video.addEventListener('canplay', doSeek, { once: true });
      // Final safety net: re-try after duration changes (HLS manifests
      // can update duration after the initial canplay event).
      video.addEventListener('durationchange', doSeek);
    }
  }

  function scanDoc(root) {
    if (!root || !root.querySelectorAll) return;
    root.querySelectorAll('video').forEach(hookVideo);
  }

  scanDoc(document);

  // Scope the per-mutation cost to only the newly-added subtrees rather
  // than re-querying the whole document on every DOM change. Streaming
  // sites mutate the DOM dozens of times per second.
  var mo = new MutationObserver(function(mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var added = mutations[i].addedNodes;
      for (var j = 0; j < added.length; j++) {
        var node = added[j];
        if (node.nodeName === 'VIDEO') hookVideo(node);
        if (node.querySelectorAll) {
          node.querySelectorAll('video').forEach(hookVideo);
        }
      }
    }
  });
  mo.observe(document.documentElement, { childList: true, subtree: true });
})();
