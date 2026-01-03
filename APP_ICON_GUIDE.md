# App Icon Guide

PUSH currently has an icon template but no actual icon images. Here's how to add one.

## What You Need

A single high-resolution icon image (1024x1024 pixels minimum).

### Icon Design Ideas

Since PUSH is a voice-to-text app, consider:

- 🎤 **Microphone icon** - Classic, immediately recognizable
- 💬 **Speech bubble** - Represents voice/text
- ⌨️ **Keyboard + microphone** - Voice-to-text concept
- 🔘 **Push button** - Plays on the "PUSH" name
- 🎙️ **Retro microphone** - Professional/podcast feel

**Recommended style:**
- Simple, bold shapes (works well at small sizes)
- High contrast
- macOS Big Sur style (rounded square, gradient acceptable)

## Tools to Create Icons

### Free Options

1. **Figma** (https://figma.com)
   - Free web-based design tool
   - Export at multiple sizes
   - Templates available

2. **Canva** (https://canva.com)
   - Easy drag-and-drop
   - Icon templates available
   - Export as PNG

3. **SF Symbols App** (macOS built-in)
   - Apple's system icons
   - Can use as starting point
   - Export and customize

### Paid Options

1. **Affinity Designer** - One-time purchase ($70)
2. **Adobe Illustrator** - Subscription

## Quick Method: Using AI

You can use AI tools to generate an icon:

**ChatGPT/DALL-E:**
```
Create a macOS app icon for a voice-to-text application called PUSH.
The icon should be a simple, modern microphone design with rounded
corners, suitable for macOS Big Sur style. 1024x1024 pixels.
```

**Midjourney:**
```
macOS app icon, microphone, voice to text, minimal, modern,
rounded square, 1024x1024 --v 6
```

## Adding the Icon to PUSH

Once you have your 1024x1024 PNG icon:

### Method 1: Automated (Recommended)

Use an online icon generator:

1. Go to https://www.appicon.co/ or https://icon.kitchen/
2. Upload your 1024x1024 icon
3. Select "macOS"
4. Download the generated iconset
5. Extract and copy all PNG files to:
   ```
   PUSH/Resources/Assets.xcassets/AppIcon.appiconset/
   ```

### Method 2: Manual

Create these sizes manually and place in `PUSH/Resources/Assets.xcassets/AppIcon.appiconset/`:

- `icon_16x16.png` - 16x16
- `icon_16x16@2x.png` - 32x32
- `icon_32x32.png` - 32x32
- `icon_32x32@2x.png` - 64x64
- `icon_128x128.png` - 128x128
- `icon_128x128@2x.png` - 256x256
- `icon_256x256.png` - 256x256
- `icon_256x256@2x.png` - 512x512
- `icon_512x512.png` - 512x512
- `icon_512x512@2x.png` - 1024x1024

Then update `Contents.json` to reference the files:

```json
{
  "images": [
    {
      "idiom": "mac",
      "scale": "1x",
      "size": "16x16",
      "filename": "icon_16x16.png"
    },
    {
      "idiom": "mac",
      "scale": "2x",
      "size": "16x16",
      "filename": "icon_16x16@2x.png"
    },
    ...
  ]
}
```

## Temporary: Use SF Symbols

For now, you can use a system icon from SF Symbols:

1. Open SF Symbols app (pre-installed on macOS)
2. Search for "mic.fill" or "waveform"
3. Export at 1024x1024
4. Use an icon generator (Method 1 above)

This gives you a functional icon while you design a custom one.

## Verifying Your Icon

After adding the icon files:

1. Rebuild the app:
   ```bash
   ./build_xcode_project.sh
   ```

2. Check the menu bar - you should see your icon
3. Open Finder and look at the .app file - it should display your icon

## Need Help?

Can't design an icon? Options:

- Use Fiverr ($5-20 for quick icon design)
- Ask in design communities (r/design_critiques)
- Use a free icon from Icons8 or Flaticon (check license)
- Keep it simple with SF Symbols

---

**For now:** The app works fine without a custom icon - it will just use a default placeholder. Add an icon when you're ready to polish for release!
