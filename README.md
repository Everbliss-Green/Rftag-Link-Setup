# RFTAG Link Setup

[RFTAG Link setup website](https://everbliss-green.github.io/Rftag-Link-Setup/)

## Overview

A Flutter web application for configuring RFTAG devices via serial connection. Supports manual input or QR code scanning to assign group IDs, frequencies, spreading factors, and update intervals.

## Features

- **Serial Communication**: Connect to RFTAG devices via Web Serial API
- **QR Code Scanning**: Scan QR codes containing device configuration
- **Automated Configuration**: Sends all necessary commands to the device
- **Terminal Output**: Real-time command logging

## QR Code Format

The app expects QR codes with the following JSON structure:

```json
{
  "groupId": "12345",
  "loraConfig": {
    "frequency": 923.875,
    "spreading_factor": "SF10",
    "location_update_interval": 60
  }
}
```

## Commands Sent

When applying settings, the following commands are sent to the device:

1. Random 8-digit group ID (to clear previous settings)
2. `rftag loc clear_history` - Clear location history
3. `rftag msg incoming clear` - Clear incoming messages
4. `rftag msg outgoing clear` - Clear outgoing messages
5. `rftag settings groupid set <groupId>` - Set group ID from QR
6. `rftag settings lora freq <frequency>` - Set LoRa frequency
7. `rftag settings lora sf <spreadingFactor>` - Set spreading factor (if provided)
8. `rftag settings timing interval <interval>` - Set update interval (if provided)

## Development

### Prerequisites

- Flutter SDK
- Chrome browser (for Web Serial API support)

### Run Locally

```bash
flutter run -d chrome
```

## Deployment to GitHub Pages

### Step-by-Step Deployment

1. **Clean previous build artifacts:**
   ```bash
   flutter clean
   ```

2. **Build for web with correct base href:**
   ```bash
   flutter build web --release --base-href "/Rftag-Link-Setup/"
   ```

3. **Copy build to docs folder:**
   ```bash
   cp -R build/web/* docs/
   ```

4. **Commit and push changes:**
   ```bash
   git add docs lib/
   git commit -m "Your commit message"
   git push
   ```

### Quick Deploy Script

You can run all commands at once:

```bash
flutter clean && \
flutter build web --release --base-href "/Rftag-Link-Setup/" && \
cp -R build/web/* docs/ && \
git add docs lib/ && \
git commit -m "Deploy updates" && \
git push
```

### Important Notes

- The `--base-href` flag must match your GitHub repository name
- The `docs/` folder is configured as the GitHub Pages source
- Changes will be live at: https://everbliss-green.github.io/Rftag-Link-Setup/
- It may take a few minutes for GitHub Pages to update after pushing

## Browser Compatibility

This app requires the **Web Serial API**, which is currently supported in:
- Chrome/Chromium (version 89+)
- Edge (version 89+)
- Opera (version 75+)

**Not supported:** Firefox, Safari
