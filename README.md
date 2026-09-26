# Satisfed

Satisfed is an iOS app that makes the food you already eat more satisfying. You show it what is on your plate, and it suggests small additions that keep you full for longer. No calorie counting, no macros, no restriction, no judgment.

Built for the RevenueCat Shipaton 2026.

## What it does

- **Plate reader.** Snap a photo of your food or pick it from the built-in library. The app reads the plate and deals a swipe deck of add-on ideas. Swipe right on what you like and get a short summary of your new plate.
- **Recipe maker.** Tell it what is in your kitchen and it turns those ingredients into satisfying meal ideas, with what goes in and how to make it.
- **Craving translator.** Describe a craving in your own words and get a read on what your body is actually asking for, plus something to eat about it.
- **Made by you.** A calendar of the plates you built, so you can see your own patterns without a single number.
- **About you.** A short profile (goal, way of eating, foods you keep off the table) that every suggestion respects.

## Business model

Satisfed is a subscription app. Every new person gets the whole app plus one complete AI feature for free. The paywall lands on the payoff screen, after the result has been shown, and offers a weekly or an annual plan with a free trial. The calendar, manual logging, and the offline food library stay open without paying.

Purchases run through the **RevenueCat SDK** (`purchases-ios`). The paywall is a native SwiftUI screen; RevenueCat supplies offerings, localized prices, trial eligibility, purchase, and restore. Entitlement checks happen server-side, so the client never decides whether an AI call is allowed.

## How it is built

| Layer | Stack |
| --- | --- |
| App | Swift, SwiftUI, SwiftData. iOS 26.5, Xcode 26.6 |
| Purchases | RevenueCat SDK, entitlement `Premium`, weekly and annual products |
| Backend | Firebase Cloud Functions (TypeScript, Node 22), Firestore, Firebase App Check with App Attest |
| AI | Azure OpenAI |

## Repository layout

```
Shiphaton App/            The iOS app (the Xcode target kept its working name)
  AI/                     Client for the Cloud Functions, response models, network monitor
  Design/                 Design system, shared components, swipe deck, calendar
  Models/                 SwiftData models, food and kitchen libraries, profile
  Purchases/              RevenueCat store, native paywall, device identity
  Root/                   Root view and tab bar
  Screens/                Onboarding, home, plate flow, recipe maker, craving translator, You tab
  Satisfed.storekit       StoreKit configuration for running the paywall on the simulator
functions/                Cloud Functions
  src/index.ts            comboAI, entitlementStatus, revenueCatWebhook
  src/entitlements.ts     Subscription check and the one-free-go ledger
  src/prompts.ts          Loads the bots' system prompts
firestore.rules           Deny-all rules
Config/Info.plist         Launch screen
```

## Running the app

1. Clone the repository and open `Shiphaton App.xcodeproj` in Xcode 26.6 or newer.
2. Let Swift Package Manager resolve the packages (Firebase, App Check, RevenueCat).
3. Pick an iOS 26.5 simulator or a device and run the `Shiphaton App` scheme.

The app builds and runs as is, and talks to our deployed backend for the AI features. The scheme already selects `Satisfed.storekit` under Run, Options, StoreKit Configuration, so the paywall shows plans on the simulator.

## Backend

The Cloud Functions source is included. The API keys, the Azure endpoint, and the AI system prompts are not, because publishing them would let anyone spend money on our accounts or copy the core of the product. To deploy your own copy, put the keys in Firebase Secret Manager, fill in `functions/.env.example`, and supply the prompt files listed in `functions/prompts/README.md`.

## Privacy

There are no accounts. The app keeps a random id in the Keychain, which doubles as the RevenueCat app user id and the key of the free-go ledger. Photos are sent to the Cloud Function only to be read and are not stored. Firebase Analytics is off in the client config.

## Team

Satisfed is built by Burak Eren Demir and İrem Duran.

## License

MIT. See [LICENSE](LICENSE).
