# Restock

A small, private shopping app that lives in one HTML file. It keeps your pantry list, learns how often you buy each item, tells you what to buy before you run out, and reads receipts with on-device OCR so purchases get logged without typing.

## What it does

- **Shopping list** – add items by hand, or let them appear automatically when they are predicted to run out. Tap the circle when you buy something and the purchase is logged for today. "Still have some" pushes an item back a few days.
- **Stock slider** – every item row has a three-position slider: Restocked (restarts the cycle from today), Used (let the prediction decide) and Buy soon (puts it on the list now).
- **Pantry** – every item with its learned interval ("every 9 days"), last purchase, next due date and a status (overdue, due soon, stocked). Set a fixed interval on any item to override the learned one.
- **Scan receipt** – photograph or upload a receipt (or paste its text). Item lines, quantities, prices, the store, date and total are extracted, matched to your pantry with fuzzy matching, and shown for review before saving. Matches you correct are remembered as aliases for next time.
- **Spending** – spend this month and last 30 days, breakdown by category and store, and items whose price moved more than 10%.
- **Settings** – how many days ahead counts as "due soon", backup/restore as JSON, example data, delete everything.

Predictions: after two purchases of an item, the median gap between purchase dates becomes its interval. Next due = last purchase + interval.

## Running it

Open `index.html` from any static web server (for example `python3 -m http.server` in this folder, then visit http://localhost:8000/). All data stays in that browser's local storage. Nothing is uploaded anywhere.

Receipt reading uses [Tesseract.js](https://github.com/naptha/tesseract.js). The engine files live in `vendor/` so the app works offline after the first load. If `vendor/` is missing (for instance when the file is opened directly from disk), the app falls back to loading the engine from a CDN.

## Receipt photos

Best results: flat receipt, even light, no shadows, text filling most of the frame. The review step lets you fix anything the reader got wrong before it is saved.

## Files

- `index.html` – the whole app (markup, styles, logic)
- `vendor/` – Tesseract.js 5.1.1, its WebAssembly core and the English language data

## License

MIT, see `LICENSE`.
