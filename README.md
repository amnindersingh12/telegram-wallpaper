# Kabe Neko - Telegram Wallpaper App

A Flutter application that automatically fetches wallpapers from Telegram channels and sets them as your phone's wallpaper.

## Features

- 📱 **Fetch Wallpapers from Telegram**: Scrapes images directly from public Telegram channels
- 🖼️ **Automatic Wallpaper Setting**: Downloads and sets images as home screen wallpaper
- ⏰ **Scheduled Updates**: Background service updates wallpapers periodically (configurable intervals)
- 💾 **Local Storage**: Wallpapers are cached locally for offline access
- ⚙️ **Easy Configuration**: Simple setup - just enter a channel username!
- 🚀 **No Backend Required (Public Channels)**: Everything runs directly in the app for public channels
- 🔒 **Optional Backend (Joined/Private Channels)**: If you want to list your joined channels (including private), run the included backend server

## Prerequisites

1. **Flutter SDK** (3.0.0 or higher)
2. **Android Studio** or **VS Code** with Flutter extensions
3. **A public Telegram channel** with wallpaper images

## Setup Instructions

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Run the App

```bash
./run.sh android    # For Android
./run.sh chrome     # For Web
./run.sh macos      # For macOS
# Or simply:
flutter run
```

### 3. Configure a Channel

1. Open the app
2. Enter a public Telegram channel username (e.g., `wallpapers`, `aesthetics`)
3. Tap "Let's Go!" to start browsing wallpapers

## Release Checklist (GitHub-safe)

Before pushing this repo to GitHub:

- Do not commit any `.env` files. Use `.env.example` as the template.
- Do not commit any Telegram secrets: `API_ID`, `API_HASH`, `SESSION_STRING`, or any Pyrogram `*.session*` files.
- Remove any local logs/build outputs if they’re present (e.g. `flutter_*.log`, `build/`, `.dart_tool/`).

Quick sanity commands:

```bash
flutter clean
flutter pub get
flutter analyze
```

If you’re using the optional backend, follow the setup in `backend/README.md` and keep all credentials local-only.

## Project Structure

```
lib/
├── screens/
│   ├── home_screen.dart           # Main wallpaper grid
│   ├── login_screen.dart          # Channel entry screen
│   ├── settings_screen.dart       # Settings and configuration
│   └── channel_browser_screen.dart # Browse saved channels
├── services/
│   ├── telegram_native_service.dart   # Native Telegram scraping
│   ├── telegram_backend_service.dart  # Main service interface
│   ├── telegram_scraper_service.dart  # Public channel scraper
│   ├── wallpaper_service.dart         # Wallpaper management
│   └── background_task_manager.dart   # Background task management
├── utils/
│   └── app_theme.dart             # Theme and styling
└── main.dart                      # App entry point
```

## How It Works

The app uses the public Telegram web preview (`t.me/s/`) to scrape images from channels. This means:
- **No API keys required** (for public scraping)
- **No backend server needed** (for public scraping)
- **Works with any public channel**

If you want to load **channels you joined** (including private/supergroups), the app can call the optional backend in `backend/`.

## Permissions Required

The app requires the following Android permissions:

- **Internet**: To fetch images from Telegram
- **Storage**: To save wallpapers locally
- **Set Wallpaper**: To change device wallpaper
- **Foreground Service**: For background updates

## Configuration Options

Available update intervals:
- 15 minutes
- 30 minutes
- 1 hour (default)
- 2 hours
- 6 hours
- 12 hours
- 24 hours

### Wallpaper Location

The app currently sets wallpapers to the **home screen**. You can modify this in `wallpaper_service.dart` to set:
- Home screen only
- Lock screen only
- Both screens

## Troubleshooting

### Wallpaper not setting
- Grant storage permission
- Check if the image was downloaded successfully
- Verify wallpaper permission is granted

### Background updates not working
- Disable battery optimization for the app
- Grant background activity permission
- Check notification permission (Android 13+)

## Dependencies

- `http` & `dio`: HTTP requests for Telegram API
- `flutter_wallpaper_manager`: Setting device wallpaper
- `workmanager`: Background task scheduling
- `flutter_background_service`: Persistent background service
- `permission_handler`: Runtime permissions
- `provider`: State management
- `path_provider`: Local file storage
- `shared_preferences`: Settings persistence
- `flutter_local_notifications`: Notifications

## Important Notes

- ⚠️ **Keep your Telegram credentials secret** - Never commit `.env`, `SESSION_STRING`, or Pyrogram `.session` files
- 📱 **Android Only** - Wallpaper setting is currently Android-specific
- 🔋 **Battery Usage** - Background updates may affect battery life
- 📶 **Network Required** - App needs internet to fetch new wallpapers

## License

This project is open source and available under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
