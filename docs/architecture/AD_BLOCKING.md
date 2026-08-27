# Ad & Popup Blocking

`assets/js/player_ad_removal.js`
`assets/js/player_is_ad.js`
`assets/js/player_adguard.js`
`lib/data/services/remote_blocklist.dart`

Three layers: a native request interceptor backed by a community
blocklist, a JS URL predicate shared by every script, and a CSS-based DOM
hide. Which layers run on which platform is covered in
[PLATFORM.md](PLATFORM.md).

---

## Layer 1 — `player_is_ad.js` (shared predicate)

Defines `window.__spoviesIsAd(url)`. Every other script delegates to it,
so the blocklist logic lives in exactly one place. Loaded first in the
`UserScript` order.

This is a *belt-and-braces* guard for substring matches that load before
the Dart side can intercept — the full ~35 k native blocklist does the
heavy lifting.

### Substring-match footgun

Every entry is matched as a raw substring against the **entire** URL.
Two rules follow from that:

- **Never add generic words.** `ads` matches `loads`, `uploads`,
  `headers`, `payloads`, `downloads` — false positives that starve
  legitimate API endpoints.
- **Never add streaming hosts.** `host-a`, `host-b`, `host-c`,
  `host-d` and friends are how aggregators fetch their server menu.
  Blocking those leaves the picker UI empty.

`brightadnetwork` deserves special mention: it is `example.com`'s
server-side redirect target. Microsoft Defender SmartScreen blocks the
domain outright and replaces the player with a red warning page when the
redirect fires. Blocking it client-side stops the redirect before
SmartScreen sees it (see the SmartScreen recovery in
[PLAYER.md](PLAYER.md#2-microsoft-defender-smartscreen-takeover)).

---

## Layer 2 — `player_ad_removal.js` (DOM + popup)

Two deliberately small pieces.

### CSS-based DOM hide

A single `<style>` element with `display:none !important` rules for known
ad selectors. The browser applies each rule to matching elements **as
they appear** — no `MutationObserver`, no `querySelectorAll` sweeps, no
`getComputedStyle` forced layouts. Dynamically-added ads are caught at
insertion time.

The style element is appended to `<html>` rather than `<head>`: at
document-start `<head>` doesn't exist yet, but `<html>` always does, and
CSS in a `<style>` applies the same wherever it is attached.

Rules also set `pointer-events: none` so an element escaping the hide via
`position:fixed; z-index:max` still cannot intercept clicks.

**Selector design rules:**

- Anchor every match on an ad-specific token — `ad-`, `ads-`,
  `adsbygoogle`, `popunder`, or a known ad-network identifier in an
  iframe `src`.
- **Never** use generic UI words alone — `popup`, `modal`, `overlay`,
  `banner`. They catch the streaming site's own server picker, quality
  menu, and caption picker, shredding the player UI.

### `window.open` allowlist

The one thing CSS cannot do. Site code calling `window.open(url)` is
checked against `__spoviesIsAd`; only ad-domain URLs are swallowed.
Legitimate popups — Cloudflare Turnstile interactive challenge, OAuth
login, share dialogs — pass through to the real `window.open` and reach
`onCreateWindow` natively.

### What was removed, and why

All of these were tried. All of them broke something.

| Removed | Broke |
|---|---|
| `MutationObserver` + `getComputedStyle` sweep | 30–100 ms forced-layout stalls on Android with Next.js pages |
| `EventTarget.prototype.addEventListener` wrapper | Sites whose own click handlers nested click dispatch — risk far exceeded the popunder protection gained |
| `document.createElement` override | Site code that legitimately creates iframes |
| `Object.defineProperty(iframe, 'src', …)` | Site bundlers that redefine iframe descriptors for their own analytics |
| `Location.prototype.assign/replace` patches | Redundant with the native `shouldOverrideUrlLoading` scheme block; the JS-side `getBase()` used a naive PSL heuristic that disagreed with the Dart side |

CSS plus one function override is the minimum that actually removes ads
and popups without becoming a bigger problem than the one it solves.

---

## Layer 3 — `player_adguard.js` (request interception)

**Windows only.** Patches `fetch`, `XMLHttpRequest`, `sendBeacon`, and
`WebSocket` to block requests to known ad domains before they leave the
WebView — mimicking DNS-level blocking without a platform-channel
round-trip per request.

On Android and iOS the native `shouldInterceptRequest` already runs every
resource through the same blocklist at the platform layer, earlier and
more cheaply. Running both has been observed breaking Cloudflare
Turnstile and some HLS shims. See
[PLATFORM.md](PLATFORM.md#needsadguardfetchpatch).

### WebSocket wrapper caveat

A naked constructor wrapper loses two things every real site depends on:

1. **Static ready-state constants** — `WebSocket.CONNECTING`, `.OPEN`,
   `.CLOSING`, `.CLOSED`. Site code writes
   `if (ws.readyState === WebSocket.OPEN)` everywhere; without them it
   evaluates `undefined === 1` and the "socket ready" branch never fires.
2. **The prototype chain** — so `ws instanceof WebSocket` still holds.

Both are restored explicitly. The static copy is written out by hand
rather than swept with `for-in` because the spec-defined properties are
`enumerable: false` in most engines and a `for-in` would miss them.

---

## Layer 4 — `RemoteBlocklist` (native interception)

A hand-curated list of ~70 domains cannot cover the thousands of ad
networks seen across streaming sites. This service maintains a living
community-driven blocklist refreshed every 24 hours.

### Sources, in preference order

| # | Source | Format | Size | Notes |
|---|---|---|---|---|
| 1 | [OISD small](https://small.oisd.nl) | domain-per-line | ~35 k | False-positive aware, streaming-friendly, updated daily |
| 2 | [Peter Lowe](https://pgl.yoyo.org/adservers/) | domain-per-line | ~4 k | Classic, high-confidence, low false positives |
| 3 | [AdGuard DNS filter](https://adguardteam.github.io/AdGuardSDNSFilter/) | `\|\|domain^` rules | ~60 k | Catches many streaming-site ad CDNs |
| 4 | [OISD big](https://big.oisd.nl) | domain-per-line | ~250 k | Aggressive; tried if small fails |
| 5 | [NoCoin](https://github.com/hoshsadiq/adblock-nocoin-list) | hosts | small | Cryptocurrency mining scripts |
| 6 | [Steven Black](https://github.com/StevenBlack/hosts) | hosts | ~100 k | Fallback of last resort — large but diverse |

**Cost profile:** O(1) `HashSet` lookup, so no per-request performance
cost. ~35 k entries ≈ 2–3 MB memory. Background-only fetch, ~800 KB
compressed for OISD small. Disk cache survives restarts, expires after
24 h.

A built-in ~70-domain fallback is always available synchronously and is
used while the remote fetch is in progress.

### Load sequence

1. Return the disk-cached list if within TTL. `existsSync` is used
   deliberately — for a single stat call there is no concurrency win and
   the async wrapper just queues a microtask. Startup-only, so blocking
   is negligible.
2. Try each remote source in order; take the first that succeeds.
   Suspiciously small responses are treated as error pages and skipped.
3. Fall back to built-in on network failure.

Never throws.

### Lookup order

1. **Exact hostname match** — for domains stored as full subdomains.
2. **Suffix walk** — catches CDN subdomains like `cdn2.acscdn.com` and
   naturally covers the registered domain (eTLD+1), since the walk visits
   every suffix `parts[i..]`. An earlier explicit eTLD+1 step was
   redundant for 3+-part hosts and only added string allocations.

An LRU cache fronts the suffix walk.

### The `Accept-Encoding` bug

There is deliberately **no** manual `Accept-Encoding` header.
`HttpClient.autoUncompress` is on by default and Dart inserts
`Accept-Encoding: gzip` itself, then transparently inflates the response.
Advertising `deflate` gave servers permission to pick a codec Dart does
**not** auto-inflate — the body reached `utf8.decoder` still compressed
and threw `FormatException: Bad UTF-8 encoding`, killing the fetch for
any source that happened to choose deflate.

The body read is bounded separately from `req.close()`: the outer
`.timeout()` only covers the latter, and a slow streaming response could
otherwise hold the connection open indefinitely while being drained.

### Parsing

Three formats are handled — bare domain per line (OISD, Peter Lowe),
hosts-file (`0.0.0.0 example.com` / `127.0.0.1 example.com`, with bare
domains also accepted), and AdGuard rules (`||example.com^`, splitting
off any options suffix like `$important` or `$dnstype=A`).

Localhost and broadcast addresses are skipped. Raw IP addresses are
rejected, and only valid domain characters are accepted.

### Providers

- `adBlocklistProvider` — async, resolves to the full remote/cached list.
- `adBlocklistFallbackProvider` — synchronous, always ready, the built-in
  ~70 domains. Used for the first few requests while the async provider
  warms up.
