#!/bin/bash
# Kabe Neko - Run Script
# Starts the Flutter app (no backend needed)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🐱 Kabe Neko - Starting...${NC}"
echo -e "${GREEN}✓ Integrated Telegram service (no backend required)${NC}"

# Run Flutter app
cd "$PROJECT_DIR"
echo -e "${GREEN}📱 Starting Flutter app...${NC}"

# Detect platform
if [[ "$1" == "android" ]]; then
    flutter run -d 34131FDH200616
elif [[ "$1" == "chrome" ]] || [[ "$1" == "web" ]]; then
    flutter run -d chrome
elif [[ "$1" == "macos" ]]; then
    flutter run -d macos
else
    # Auto-detect: prefer Chrome/web if no Android device
    if flutter devices | grep -q "android"; then
        flutter run -d android
    else
        echo -e "${YELLOW}No Android device found. Running on Chrome...${NC}"
        flutter run -d chrome
    fi
fi
