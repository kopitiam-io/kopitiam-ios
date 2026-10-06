# Kopitiam — Store Assets

Brand: warm-kopi. Icon mark = one cream coffee cup + saucer with two burnt-orange
steam wisps on a brand-brown→burnt-orange gradient. Palette: brand-brown `#4A2C1A`,
burnt-orange `#C05621`, cream `#F7F1E8`.

All raster assets are derived from the single 1024×1024 master
`ios-native/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
so iOS and Android share one identical brand mark.

## iOS (`ios/`)

### `ios/icons/` — full App Store icon set (15 sizes)
Generated with `sips` from the 1024 master. Covers every iPhone/iPad slot plus the
1024 App Store marketing icon:

| Slot            | px  | file |
|-----------------|-----|------|
| Notification    | 40/60          | AppIcon-20@2x/@3x |
| Settings        | 58/87          | AppIcon-29@2x/@3x |
| Spotlight       | 80/120         | AppIcon-40@2x/@3x |
| App (iPhone)    | 120/180        | AppIcon-60@2x/@3x |
| App (iPad)      | 76/152/167     | AppIcon-76*, 83.5@2x |
| App Store       | 1024           | AppIcon-1024@1x |

The live app already ships the single-size 1024 catalog (Xcode 14+ auto-generates
the rest at build). This folder is the explicit full set for App Store Connect /
older tooling.

### `ios/screenshots/` — App Store screenshots (1206×2622, 6.9" class)
- `01-home.png` — hero: "Every PDF tool, free." + tool grid (VERIFIED)
- `02-redact-detail.png` — Redact tool detail (VERIFIED)

## Android (`android/`)

### `android/icons/`
- `play-store-icon-512.png` — **required** Play Store listing icon (512×512)
- `ic_launcher-{mdpi..xxxhdpi}.png` — legacy launcher PNG fallbacks (pre-API 26;
  API 26+ uses the vector adaptive icon in `app/src/main/res/`)

### `android/feature-graphic-1024x500.png` — **required** Play Store feature graphic
Brand gradient + coffee-cup mark + "Kopitiam / Every PDF tool, free." wordmark.
Rendered pixel-accurate in a browser at a 1024×500 viewport (VERIFIED).
Source: `android/feature-graphic.svg` / `android/fg.html`.

## Known gap — deeper feature screenshots
Home + one tool-detail screen are captured at store resolution. The *working*
feature screens (editor with a loaded PDF, live OCR result, scan-filter preview,
Convert modes) need a document loaded via the picker — that interactive flow was
verified live during the builds but cannot be re-driven reliably from this
off-display simulator via automation. Capture those on a physical device (or in a
foreground simulator you can tap) before submitting: launch the tool → Choose a PDF
→ screenshot the working state. Same applies to Android working-feature shots.

## Play / App Store screenshot spec (for reference)
- **iOS 6.9"**: 1290×2796 or 1206×2622 (this set). Up to 10 per device class.
- **Android phone**: 1080×1920+ (min 320px, max 3840px, 2:1 max ratio). 2–8 shots.
- **Android feature graphic**: exactly 1024×500 (provided).
- **Android icon**: exactly 512×512, 32-bit PNG (provided).
