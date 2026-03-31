#!/bin/bash
# ============================================================
# AOT Release Automator - xprateek
# ============================================================
# Usage: ./release.sh
#
# Branch-aware:
#   - main  → Stable Release ZIP: AOT-Tether-vX.Y.Z-REL.zip
#   - dev   → Dev Pre-Release ZIP: AOT-Tether-vX.Y.Z-PRE.zip
# ============================================================

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}---------------------------------------${NC}"
echo -e "${CYAN}  AOT Release Automator (v2.0)         ${NC}"
echo -e "${CYAN}---------------------------------------${NC}"

# ============================================================
# 1. Detect current branch
# ============================================================
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo -e "${CYAN}Branch: ${YELLOW}$BRANCH${NC}"

if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    ZIP_SUFFIX="REL"
    RELEASE_TYPE="Stable"
elif [ "$BRANCH" = "dev" ]; then
    ZIP_SUFFIX="PRE"
    RELEASE_TYPE="Pre-Release"
else
    echo -e "${RED}Error: Must be on 'main' or 'dev' branch. Currently on: $BRANCH${NC}"
    exit 1
fi

echo -e "${CYAN}Release type: ${YELLOW}$RELEASE_TYPE${NC}"

# ============================================================
# 1.5. Check for RC override
# ============================================================
read -p "Is this a Release Candidate (RC)? (y/N): " IS_RC
if [[ "$IS_RC" =~ ^[Yy]$ ]]; then
    ZIP_SUFFIX="RC"
    RELEASE_TYPE="Release Candidate"
fi

# ============================================================
# 2. Get Version Info
# ============================================================
read -p "Enter new version (e.g., 1.0.3): " VER
if [ -z "$VER" ]; then
    echo -e "${RED}Error: Version cannot be empty.${NC}"
    exit 1
fi

FULL_VER="v$VER"
# Proper versionCode: major*10000 + minor*100 + patch (e.g., 1.0.3 → 10003)
MAJOR=$(echo $VER | cut -d. -f1)
MINOR=$(echo $VER | cut -d. -f2)
PATCH=$(echo $VER | cut -d. -f3)
PATCH=${PATCH:-0}
VER_CODE=$(( MAJOR * 10000 + MINOR * 100 + PATCH ))
ZIP_NAME="AOT-Tether-${FULL_VER}-${ZIP_SUFFIX}.zip"

echo -e "${YELLOW}Bumping to $FULL_VER (Code: $VER_CODE) → $ZIP_NAME${NC}"

# ============================================================
# 3. Get Changelog Entry
# ============================================================
read -p "Enter change description: " DESC
read -p "Any special credits? (Leave empty if none): " CREDITS

# ============================================================
# 4. Update module.prop
# ============================================================
sed -i "s/^version=.*/version=$FULL_VER/" module/module.prop
sed -i "s/^versionCode=.*/versionCode=$VER_CODE/" module/module.prop
sed -i "s/description=\[v[^]]*\]/description=[$FULL_VER Release Candidate]/" module/module.prop
echo -e "${GREEN}[✓] Updated module.prop${NC}"

# ============================================================
# 5. Update update.json (only on main/stable)
# ============================================================
if [ "$ZIP_SUFFIX" = "REL" ]; then
    sed -i "s/\"version\": \".*\"/\"version\": \"$FULL_VER\"/" update.json
    sed -i "s/\"versionCode\": .*/\"versionCode\": $VER_CODE,/" update.json
    sed -i "s|releases/download/.*/AOT-Tether-.*-REL.zip|releases/download/$FULL_VER/AOT-Tether-${FULL_VER}-REL.zip|" update.json
    echo -e "${GREEN}[✓] Updated update.json (Stable OTA track)${NC}"
else
    echo -e "${YELLOW}[~] Skipping update.json (dev track — not OTA-served)${NC}"
fi

# ============================================================
# 6. Update WebUI Version
# ============================================================
sed -i "s/\"version\": \".*\"/\"version\": \"$VER\"/" webui/package.json
sed -i "s|id=\"version-text\">v.*</span>|id=\"version-text\">$FULL_VER</span>|" webui/index.html
echo -e "${GREEN}[✓] Updated WebUI Version${NC}"

# ============================================================
# 7. Update CHANGELOG.md
# ============================================================
DATE=$(date +%Y-%m-%d)
{
    echo -e "# 📓 AOT Changelog\n"
    echo -e "## $FULL_VER - $DATE ($RELEASE_TYPE)"
    echo -e "*   **$DESC**"
    if [ -n "$CREDITS" ]; then
        echo -e "*   **Special Thanks**: $CREDITS"
    fi
    echo -e "\n---"
    sed '1d' CHANGELOG.md | sed '/./,$!d'
} > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
echo -e "${GREEN}[✓] Updated CHANGELOG.md${NC}"

# ============================================================
# 8. Build WebUI & Package ZIP
# ============================================================
echo -e "${YELLOW}Building WebUI and Packaging Module...${NC}"
npm --prefix webui run build > /dev/null 2>&1
rm -f module/aot.log
rm -f AOT-Tether-v*.zip
cd module && zip -r9 ../$ZIP_NAME * > /dev/null 2>&1 && cd ..
echo -e "${GREEN}[✓] Built $ZIP_NAME${NC}"

# ============================================================
# 9. Git: Commit, Tag, Push
# ============================================================
echo -e "${YELLOW}Staging and Pushing to GitHub (with Tags)...${NC}"
git add .
git commit -m "fix: $FULL_VER $RELEASE_TYPE - $DESC" --signoff

if [ "$ZIP_SUFFIX" = "REL" ]; then
    # Stable: push versioned tag (v1.0.3)
    git tag -f "$FULL_VER"
    git push origin "$BRANCH"
    git push origin "$FULL_VER" -f
else
    # Dev: push without versioned tag (CI handles dev-pre rolling tag)
    git push origin dev
fi
echo -e "${GREEN}[✓] Pushed to GitHub${NC}"

# ============================================================
# 10. Device Sync via ADB (optional)
# ============================================================
echo -e "${YELLOW}Pushing to Device via ADB...${NC}"
if adb devices | grep -q "device$"; then
    adb push "$ZIP_NAME" "/sdcard/Download/$ZIP_NAME"
    echo -e "${GREEN}[✓] Pushed to /sdcard/Download/${NC}"
else
    echo -e "${YELLOW}[~] No ADB device found — skipping device push${NC}"
fi

echo -e "${GREEN}---------------------------------------${NC}"
echo -e "${GREEN}  Release $FULL_VER ($RELEASE_TYPE)   ${NC}"
echo -e "${GREEN}  ZIP: $ZIP_NAME                       ${NC}"
echo -e "${GREEN}  Pushed Successfully!                  ${NC}"
echo -e "${GREEN}---------------------------------------${NC}"
