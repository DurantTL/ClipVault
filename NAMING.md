# App Naming Strategy

The final product name is still open because the short brand name may already be reserved in App Store Connect. Instead of abandoning a strong base brand immediately, test a more distinctive full App Store name by pairing the brand with a short description of what the app does.

Example pattern:

    Brand: Video Ingest

This follows the same approach as a generic example such as `Basketball App: Coaching & Form`: the recognizable brand remains first, while the descriptive phrase makes the complete name more distinctive and easier to understand in search results.

## Apple limits

Apple currently allows:

- App name: 2–30 characters.
- Subtitle: up to 30 characters.

Official references:

- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/app-store/product-page/

The exact full app name must still be tested in App Store Connect. Adding a descriptive phrase can provide more naming flexibility, but it does not guarantee availability or approval.

## Recommended structure

Use three separate naming layers:

1. **Base brand** — the short memorable product identity used in the logo and most in-app copy.
2. **App Store name** — the base brand plus a concise functional phrase when needed for availability and clarity.
3. **Subtitle** — a second short phrase describing the workflow or benefit without repeating the name.

Example:

    Base brand: SlateBox
    App Store name: SlateBox: Video Ingest
    Subtitle: Verify, Cull & Hand Off

The product can keep a short in-app identity while the App Store listing uses the fuller name. Keep the two recognizable as the same product.

## Name patterns to test

Substitute the final base brand into several exact App Store Connect candidates:

- `<Brand>: Video Ingest`
- `<Brand>: Ingest & Cull`
- `<Brand>: Media Offload`
- `<Brand>: Video Workflow`
- `<Brand>: Ingest & Organize`
- `<Brand>: Video Card Manager`

For the current working name, examples include:

- `SlateBox: Video Ingest`
- `SlateBox: Ingest & Cull`
- `SlateBox: Media Offload`

Test more than one exact variation because App Store Connect availability applies to the complete submitted name, not merely the desired base word.

## Subtitle ideas

Keep the subtitle useful and avoid simply repeating the app name:

- `Verify, Cull & Hand Off`
- `Safe Ingest for Filmmakers`
- `Offload, Review and Organize`
- `Copy, Verify and Select`
- `Fast Video Ingest Workflow`

Character counts must be checked before entering the final text in App Store Connect.

## Selection rules

The final name should:

- Put the distinctive brand first.
- Hint clearly at video ingest, offload, culling, or media organization.
- Be easy to say, spell, search, and remember.
- Fit within Apple's current 30-character app-name limit.
- Avoid competitor names, camera trademarks, unsupported claims, and keyword stuffing.
- Leave enough flexibility for the product to grow beyond a single camera model or one ingest workflow.

Apple recommends a simple, memorable, distinctive app name that hints at what the app does. Use the subtitle for additional value or feature language rather than forcing every keyword into the name.

## Technical naming policy

Changing the public product name must not change the permanent project-format identifiers:

- `.clipvault-project.json`
- `.clipvault-cache`
- `.clipvault-partial`
- `~/Library/Caches/ClipVault/`

Those identifiers remain stable so old projects continue to open. User-visible branding continues to flow through `AppBrand.swift`, followed by the rename checklist documented there for the Xcode target, bundle identifier, scheme, CI, icon, and documentation.

## Decision process

Before committing to the final brand:

1. Prepare at least three base-brand candidates.
2. Create three to five full App Store name variations for each candidate.
3. Check exact availability in App Store Connect.
4. Check obvious trademark, domain, and search-result conflicts separately.
5. Choose the strongest available combination of base brand, App Store name, and subtitle.
6. Update `AppBrand.swift`, Xcode identifiers, CI, documentation, icon assets, and marketing copy together.
