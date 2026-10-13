# Restock

A private shopping app for iPhone (and any browser) that lives in one HTML file. It keeps your pantry, learns how often you buy each item, tells you what to buy before you run out, and reads receipts with on-device OCR so purchases get logged without typing.

## Install on iPhone

Restock is a web app you add to your home screen. Host this folder on any static site (GitHub Pages works), open it in Safari, tap **Share**, then **Add to Home Screen**. It then opens full screen with its own icon and keeps working offline, including receipt reading.

## What it does

- **Shopping list** – items appear automatically when they are predicted to run out, or add them by hand. Tap the circle when you buy something: it animates away and the purchase is logged for today, with undo.
- **Stock control** – every row has a three-position control: Restocked (restarts the cycle from today), Used (let the prediction decide) and Buy soon (puts it on the list now). Tap a row to reveal details and actions.
- **Pantry** – every item with its learned interval, last purchase, next due date and status. Set a fixed interval on any item to override.
- **Scan receipt** – photograph a receipt, or try the built-in sample. A scanning sweep runs while the text is read, then the recognised lines light up on the photo and land in an editable list, matched to your pantry. Corrections are remembered as aliases.
- **Spending** – this month and last 30 days, breakdown by category and store, and items whose price moved more than 10%.
- **Settings** – "due soon" threshold, backup and restore as JSON, example data, delete everything.

Predictions: after two purchases of an item, the median gap between purchase dates becomes its interval. Next due = last purchase (or the day you marked it Restocked) + interval.

## Running it locally

Serve the repository root with any static server (for example `python3 -m http.server`) and open `/restock/`. All data stays in that browser. Nothing is uploaded anywhere.

Receipt reading uses [Tesseract.js](https://github.com/naptha/tesseract.js). The engine files live in `vendor/` and a service worker (`sw.js`) caches them, so the app works offline after the first load. If `vendor/` is missing, the app falls back to loading the engine from a CDN.

## Files

- `index.html` – the whole app (markup, styles, logic)
- `manifest.webmanifest`, `sw.js`, `icon-*.png` – home-screen install and offline cache
- `vendor/` – Tesseract.js 5.1.1, its WebAssembly core and the English language data

## License

MIT, see `LICENSE` at the repository root.
