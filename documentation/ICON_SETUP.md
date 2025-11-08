# App Icon Setup

An SVG icon has been created at `app-icon.svg`. To use it as your app icon, you need to convert it to PNG files at various sizes.

## Option 1: Using ImageMagick (Command Line)

If you have ImageMagick installed (`brew install imagemagick`), you can run:

```bash
# Navigate to the WhisperKit Transcriber directory
cd "WhisperKit Transcriber"

# Generate all required PNG sizes
magick app-icon.svg -resize 16x16 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_16x16.png"
magick app-icon.svg -resize 32x32 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png"
magick app-icon.svg -resize 32x32 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_32x32.png"
magick app-icon.svg -resize 64x64 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png"
magick app-icon.svg -resize 128x128 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_128x128.png"
magick app-icon.svg -resize 256x256 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png"
magick app-icon.svg -resize 256x256 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"
magick app-icon.svg -resize 512x512 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"
magick app-icon.svg -resize 512x512 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
magick app-icon.svg -resize 1024x1024 "WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
```

Then update `Contents.json` to reference these files.

## Option 2: Using Online Converter

1. Go to https://cloudconvert.com/svg-to-png or similar
2. Upload `app-icon.svg`
3. Convert to PNG at 1024x1024
4. Use Preview.app or another tool to resize to the required sizes:
   - 16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024
5. Drag the PNG files into the AppIcon.appiconset folder in Xcode

## Option 3: Using Xcode

1. Open the project in Xcode
2. Select `Assets.xcassets` > `AppIcon`
3. Drag the SVG file into Xcode (it will auto-generate sizes)
4. Or manually drag PNG files at each size into the appropriate slots

## Quick Setup Script

If you have ImageMagick, you can use this script:

```bash
#!/bin/bash
SVG="app-icon.svg"
ASSETS_DIR="WhisperKit Transcriber/Assets.xcassets/AppIcon.appiconset"

sizes=(16 32 32 64 128 256 256 512 512 1024)
names=("icon_16x16.png" "icon_16x16@2x.png" "icon_32x32.png" "icon_32x32@2x.png"
       "icon_128x128.png" "icon_128x128@2x.png" "icon_256x256.png" "icon_256x256@2x.png"
       "icon_512x512.png" "icon_512x512@2x.png")

for i in "${!sizes[@]}"; do
    magick "$SVG" -resize "${sizes[$i]}x${sizes[$i]}" "$ASSETS_DIR/${names[$i]}"
done

echo "Icons generated! Now update Contents.json in Xcode."
```

