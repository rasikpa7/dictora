# Dictora website — project document

Marketing site for the Dictora Mac app. Static HTML on Firebase Hosting.

## Layout
- `Website/public/` — the site (index, privacy, 404, robots, sitemap, og image, `downloads/`)
- `Website/firebase.json` — hosting config, security and cache headers
- `docs/marketing/` — marketing assets and copy (positioning, launch copy)
- `docs/website.md` — this file

## Positioning
Completely free. Powered by the Apple Intelligence on your Mac. Fast, seamless, any app.
Cloud AI providers are future work and are deliberately NOT mentioned on the site.

## Deploy
From `Website/`: `firebase deploy --only hosting` (account: see Hosting section below).

## Release a new version of the app
1. Build a signed Release app and zip it: `ditto -c -k --keepParent Dictora.app Dictora-<version>.zip`. (A DMG is rejected by Firebase Hosting on the free Spark plan: "Executable files are forbidden". A signed DMG is kept in `dist/`; it can be hosted after upgrading to Blaze or moving downloads elsewhere.)
2. Put it in `Website/public/downloads/Dictora-<version>.zip`.
3. Update the version, size and `href`s in `public/index.html` (three download buttons and the size).
4. `firebase deploy --only hosting`.

## Analytics
Google Analytics for Firebase via the reserved `/__/firebase/init.json`. Events:
`page_view` (automatic), `download_app` (location: nav/hero/footer), `cta_apple_intelligence`,
`demo_style_selected`, `faq_open`, `scroll_depth` (25/50/75/100). Skipped when Do Not Track /
Global Privacy Control is on or the visitor chose "Turn off analytics" in the footer.
Disclosed in `public/privacy.html`.

## Known limitations
- The DMG is signed with an Apple Development certificate and is NOT notarized, so Gatekeeper
  blocks the first launch (Control-click → Open). Notarizing needs a Developer ID certificate
  from a paid Apple Developer account. The FAQ on the site explains the workaround.
- No contact address is published. Add one to the footer/privacy page when you have it.
- Visuals in the demo are illustrations, not screenshots.
