# TaoTronics AC3000 Wi-Fi Router App

A Flutter-based local control app for TaoTronics AC3000 Mesh Wi-Fi Routers.

[![Download APK](https://img.shields.io/badge/Download-APK-green?style=for-the-badge&logo=android)](https://github.com/alfeyo/Taotronics-AC3000-Wi-Fi-App/raw/main/releases/TaoTronics-Router-App.apk)

## About

This app provides local network control for TaoTronics AC3000 mesh routers without requiring cloud connectivity or the original vendor app (which is no longer supported/available).

### Features

- **Router Discovery**: Automatic discovery of TaoTronics mesh routers on your local network
- **MQTT Control**: Direct local communication with router via MQTT protocol
- **Dashboard**: View mesh nodes, connected devices, and live network throughput
- **Wi-Fi Settings**: View and edit Wi-Fi network names (SSIDs) and passwords
- **Device Management**: See all connected devices with their IP/MAC addresses
- **Diagnostics**: Network connectivity checks and troubleshooting tools

## Legal Disclaimer

**THIS SOFTWARE IS PROVIDED FOR PERSONAL, NON-COMMERCIAL USE ONLY.**

This project is:
- **NOT affiliated with, endorsed by, or connected to TaoTronics, RAVPower, or any related companies**
- **NOT intended for sale or commercial distribution**
- **Provided as-is, without warranty of any kind**

### Purpose

This app was created because:
1. The original TaoTronics/TT Router app has been discontinued and removed from app stores
2. Router owners deserve continued access to manage their own hardware
3. Local network control should not depend on cloud services that may be discontinued

### Fair Use

This project is provided to help owners of TaoTronics AC3000 routers maintain control over their own devices. The router hardware belongs to the user, and this app simply provides an interface to manage it locally.

**By using this software, you acknowledge that:**
- You own or have authorized access to the router you are controlling
- You will not use this software for any illegal purposes
- You will not redistribute this software for commercial gain
- The developers are not responsible for any issues arising from use of this software

## Download

**[Download APK](https://github.com/alfeyo/Taotronics-AC3000-Wi-Fi-App/raw/main/releases/TaoTronics-Router-App.apk)** - Ready-to-install Android app

To install:
1. Download the APK file
2. Enable "Install from unknown sources" in your Android settings
3. Open the APK file to install

## Requirements

- Android device (Android 6.0+)
- TaoTronics AC3000 Mesh Router on your local network
- Device must be connected to the router's Wi-Fi network

## Building

```bash
# Install Flutter SDK
# Clone this repository
git clone https://github.com/alfeyo/Taotronics-AC3000-Wi-Fi-App.git
cd Taotronics-AC3000-Wi-Fi-App

# Get dependencies
flutter pub get

# Build debug APK
flutter build apk --debug

# Install on connected device
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Usage

1. Connect your phone to your TaoTronics router's Wi-Fi network
2. Open the app
3. The app will automatically discover your router
4. Tap "Continue to Dashboard" to access router controls

## Contact

For questions, issues, or contributions:
- **Email**: alfeyokatebe@gmail.com
- **GitHub Issues**: https://github.com/alfeyo/Taotronics-AC3000-Wi-Fi-App/issues

## License

This project is for personal use only. See the Legal Disclaimer section above.

---

*This project is not affiliated with TaoTronics, RAVPower, Sunvalley Group, or any of their subsidiaries.*
