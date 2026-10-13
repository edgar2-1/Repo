# Restock

A private shopping app for iPhone (and any browser) that lives in one HTML file. It keeps your pantry, learns how often you buy each item, tells you what to buy before you run out, and reads receipts with on-device OCR so purchases get logged without typing.

## Install on iPhone

Restock is a web app you add to your home screen. Host this folder on any static site (GitHub Pages works), open it in Safari, tap **Share**, then **Add to Home Screen**. It then opens full screen with its own icon and keeps working offline, including receipt reading.

## What it does

- **Shopping list** – items appear a few days before they're predicted to run out. Quick add takes several at once with quantities: `2 oat milk, eggs, limes x3`, with suggestions from your pantry.
- **Shopping trips** – tick items into the cart as you shop (or swipe right). A cart bar shows the running total; **Finish trip** logs everything with prices prefilled from what you last paid at that store. The screen stays awake while items are in the cart.
- **Store aware** – each item learns your usual store. Group the list by store with a subtotal for each, and get "due soon, add while you're there" suggestions for the same store. Every item shows its price at each store you've bought it, with the lowest marked.
- **Stock control** – every item has Restocked / Used / Buy soon.
- **Receipt scanning** – photograph a receipt (or try the built-in sample). Lines are read on the device, highlighted on the photo, matched to your pantry, and saved as a trip.
- **Products and nutrition** – after a scan, each line is matched to a real product in [Open Food Facts](https://world.openfoodfacts.org): photo, brand, Nutri-Score, calories and a full nutrition table per 100 g, plus a Nutri-Score summary for the whole shop. Matches start as suggestions you confirm; you can pick another or type the barcode for an exact match. Searches are paced to Open Food Facts' rate limit and retried when the service is busy.
- **Reminders** – a count of items to buy on the app icon (Home Screen app, iOS 16.4+), and a weekly shopping-day event with an alert you can add to Calendar.
- **Share** – send the list as text, grouped by store, from the iOS share sheet.
- **Spending** – monthly budget with pace, spend by aisle, a history of trips you can open, and price changes.
- **Gestures** – swipe right to put in the cart (or add to the list from Pantry), swipe left to snooze or delete, tap for details in a sheet. Everything undoable.

Predictions: after two purchases of an item, the median gap between purchase dates becomes its interval. Next due = last purchase (or the day you marked it Restocked) + interval.

## Running it locally

Serve the repository root with any static server (for example `python3 -m http.server`) and open `/restock/`. Your lists and purchases stay in that browser. The only network calls are product searches to Open Food Facts, which send the item name and nothing else.

Receipt reading uses [Tesseract.js](https://github.com/naptha/tesseract.js). The engine files live in `vendor/` and a service worker (`sw.js`) caches them, so the app works offline after the first load. If `vendor/` is missing, the app falls back to loading the engine from a CDN.

## Files

- `index.html` – the whole app (markup, styles, logic)
- `manifest.webmanifest`, `sw.js`, `icon-*.png` – home-screen install and offline cache
- `vendor/` – Tesseract.js 5.1.1, its WebAssembly core and the English language data

## License

MIT, see `LICENSE` at the repository root.
