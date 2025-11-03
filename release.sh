#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/LookAway.xcodeproj/project.pbxproj"
SCHEME="LookAway"
RELEASES_DIR="$PROJECT_DIR/Releases"

echo -e "${BLUE}=== LookAway Release Builder ===${NC}\n"

# Check for clean working directory
if ! git diff-index --quiet HEAD --; then
    echo -e "${RED}Error: Working directory is not clean.${NC}"
    echo -e "${YELLOW}Please commit or stash your changes before creating a release.${NC}\n"
    git status --short
    exit 1
fi

echo -e "${GREEN}✓ Working directory is clean${NC}\n"

# Get current version
CURRENT_VERSION=$(grep -m 1 "MARKETING_VERSION = " "$PROJECT_FILE" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/')
echo -e "Current version: ${GREEN}$CURRENT_VERSION${NC}\n"

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Prompt for release type if not provided
if [ -z "$1" ]; then
    echo "Select release type:"
    echo "  1) Major ($MAJOR.x.x -> $((MAJOR+1)).0.0)"
    echo "  2) Minor ($MAJOR.$MINOR.x -> $MAJOR.$((MINOR+1)).0)"
    echo "  3) Patch ($MAJOR.$MINOR.$PATCH -> $MAJOR.$MINOR.$((PATCH+1)))"
    echo ""
    read -p "Enter choice (1-3): " CHOICE

    case $CHOICE in
        1) RELEASE_TYPE="major" ;;
        2) RELEASE_TYPE="minor" ;;
        3) RELEASE_TYPE="patch" ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
else
    RELEASE_TYPE="$1"
fi

# Calculate new version
case $RELEASE_TYPE in
    major)
        NEW_VERSION="$((MAJOR+1)).0.0"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR+1)).0"
        ;;
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH+1))"
        ;;
    *)
        echo -e "${RED}Invalid release type: $RELEASE_TYPE (use: major, minor, or patch)${NC}"
        exit 1
        ;;
esac

echo -e "\n${YELLOW}New version will be: $NEW_VERSION${NC}"
read -p "Continue? (y/n): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Release cancelled.${NC}"
    exit 0
fi

# Update version in project.pbxproj
echo -e "\n${BLUE}Updating version in project...${NC}"
sed -i '' "s/MARKETING_VERSION = $CURRENT_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" "$PROJECT_FILE"
echo -e "${GREEN}✓ Version updated to $NEW_VERSION${NC}"

# Create archive
echo -e "\n${BLUE}Creating archive...${NC}"
ARCHIVE_PATH="$PROJECT_DIR/DerivedData/Archives/$SCHEME-$NEW_VERSION.xcarchive"
xcodebuild archive \
    -scheme "$SCHEME" \
    -project "$PROJECT_DIR/LookAway.xcodeproj" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    | grep -E '(BUILD SUCCEEDED|ARCHIVE SUCCEEDED|FAILED|error:)' || true

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo -e "${RED}✗ Archive failed!${NC}"
    # Revert version change
    sed -i '' "s/MARKETING_VERSION = $NEW_VERSION;/MARKETING_VERSION = $CURRENT_VERSION;/g" "$PROJECT_FILE"
    echo -e "${YELLOW}Version reverted to $CURRENT_VERSION${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Archive created${NC}"

# Export archive using -exportArchive with method "mac-application" (Copy App equivalent)
echo -e "\n${BLUE}Exporting app...${NC}"
TIMESTAMP=$(date +"%Y-%m-%d %H-%M-%S")
EXPORT_DIR="$RELEASES_DIR/$SCHEME $TIMESTAMP"
EXPORT_PLIST="$PROJECT_DIR/DerivedData/export-options.plist"

# Create export options plist for "Copy App" method
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

mkdir -p "$EXPORT_DIR"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    | grep -E '(EXPORT SUCCEEDED|FAILED|error:)' || true

if [ ! -f "$EXPORT_DIR/$SCHEME.app/Contents/Info.plist" ]; then
    echo -e "${RED}✗ Export failed!${NC}"
    # Revert version change
    sed -i '' "s/MARKETING_VERSION = $NEW_VERSION;/MARKETING_VERSION = $CURRENT_VERSION;/g" "$PROJECT_FILE"
    echo -e "${YELLOW}Version reverted to $CURRENT_VERSION${NC}"
    exit 1
fi

echo -e "${GREEN}✓ App exported to: $EXPORT_DIR${NC}"

# Verify version in exported app
EXPORTED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$EXPORT_DIR/$SCHEME.app/Contents/Info.plist")
echo -e "${GREEN}✓ Verified app version: $EXPORTED_VERSION${NC}"

# Commit version change and release build
echo -e "\n${BLUE}Committing version change and release build...${NC}"
echo -e "Enter commit body (optional, leave blank for subject only):"
read -p "> " COMMIT_BODY

COMMIT_SUBJECT="chore(release): $NEW_VERSION"

git add "$PROJECT_FILE"
git add "$EXPORT_DIR"
if [ -z "$COMMIT_BODY" ]; then
    git commit -m "$COMMIT_SUBJECT"
else
    git commit -m "$COMMIT_SUBJECT" -m "$COMMIT_BODY"
fi
echo -e "${GREEN}✓ Version and release build committed${NC}"

echo -e "\n${GREEN}=== Release Complete ===${NC}"
echo -e "Version: ${GREEN}$NEW_VERSION${NC}"
echo -e "Location: ${BLUE}$EXPORT_DIR/$SCHEME.app${NC}"
echo -e "\nTo install:"
echo -e "\ncp -r \"$EXPORT_DIR/$SCHEME.app\" /Applications/"
