# Restock for iPhone

The native iPhone version of Restock: a shopping list that learns how often you buy things and tells you before you run out. Built with SwiftUI for iOS 17 and later.

## What's in it

- **Shopping list** – items appear a few days before they're predicted to run out. Quick add takes several at once with quantities (`2 oat milk, eggs, limes x3`) and suggests pantry items as you type.
- **Shopping trips** – tick or swipe items into the cart, see the running total, then **Finish trip** to log everything with prices prefilled from your last visit to that store.
- **Store aware** – learns each item's usual store, groups the list by store with subtotals, suggests items due soon at the same store, and shows each item's price at every store.
- **Stock control** – Restocked / Used / Buy soon on every item.
- **Receipt scanning** – Apple's document camera flattens the receipt and the Vision framework reads it on the device. Lines are matched to your pantry and saved as a trip.
- **Products and nutrition** – each receipt line is matched to a product in [Open Food Facts](https://world.openfoodfacts.org): photo, brand, Nutri-Score and nutrition facts. Scan a barcode for an exact match.
- **Reminders** – local notifications when items are about to run out, a weekly shopping-day reminder, and the to-buy count on the app icon.
- **Spending** – monthly budget with pace, spend by aisle chart, trip history and price changes.
- **Backup** – export as JSON, or restore a backup from the Restock web app.

## Layout

```
restock-ios/
├── project.yml                 XcodeGen spec (generates Restock.xcodeproj)
├── Packages/RestockKit/        all logic, no UI; builds and tests on macOS and Linux
│   ├── Sources/RestockKit/     models, predictions, receipt parser, quick add,
│   │                           trips, stores and prices, reminders, Open Food Facts client
│   └── Tests/RestockKitTests/  unit tests, including a real web-app backup fixture
└── Restock/                    the SwiftUI app
    ├── AppModel.swift          state, persistence, undo, reminders, product matching
    ├── Services/               text recognition, document and barcode scanners, notifications
    └── Views/                  Shopping, Pantry, Scan, Spending, Settings, item and trip detail
```

The logic in RestockKit is a port of the web app (`../restock`) and is tested against the same receipts.

## Build and run

You need a Mac with Xcode 15 or later.

```sh
brew install xcodegen
cd restock-ios
xcodegen generate
open Restock.xcodeproj
```

Pick an iPhone simulator and press Run. The camera scanners need a real iPhone; on the simulator use **Choose a photo**, **Paste receipt text** or **Try a sample receipt**.

Run the logic tests without Xcode:

```sh
swift test --package-path Packages/RestockKit
```

GitHub Actions builds the app and runs the tests on every push that touches `restock-ios/` (`.github/workflows/restock-ios.yml`).

## Getting it onto the App Store

These steps need your Apple account, so they can't be automated from here.

1. **Join the Apple Developer Program** ($99 a year) at developer.apple.com.
2. **Choose a bundle id** you own, for example `com.yourname.restock`, and set it as `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`. Put your Team ID in `DEVELOPMENT_TEAM`, then run `xcodegen generate` again.
3. **Create the app in App Store Connect** and reserve its name. "Restock" may already be taken; have a second choice ready.
4. **Run it on your iPhone** from Xcode, and use it for real shopping for a week or two.
5. **Archive and upload**: in Xcode choose Product > Archive, then Distribute App > App Store Connect. Install it from **TestFlight** to test the release build.
6. **Fill in the listing**: description, keywords, screenshots (iPhone, largest size), support URL and a **privacy policy URL**.
7. **Privacy answers**: Restock collects no data. Lists, purchases and photos stay on the device; only item names are sent to Open Food Facts to look up products, with no identifiers. The app includes a privacy manifest (`PrivacyInfo.xcprivacy`) and declares no encryption beyond HTTPS.
8. **Submit for review.** The example pantry (Settings > Load example pantry) and the sample receipt let a reviewer try everything without shopping.

Open Food Facts data is under the Open Database License, and product photos are CC BY-SA. The app credits Open Food Facts wherever its data appears and in Settings > About.
