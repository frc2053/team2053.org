#!/bin/bash

# Find duplicate images in public/assets/images using perceptual hashing
# This will find images that look similar even if they're different sizes/formats

IMAGES_DIR="public/assets/images"

echo "🔍 Finding duplicate images in $IMAGES_DIR..."
echo "This may take a minute..."
echo ""

# Check if findimagedupes is installed
if ! command -v findimagedupes &> /dev/null; then
    echo "❌ findimagedupes is not installed!"
    echo ""
    echo "Install it with:"
    echo "  Ubuntu/Debian: sudo apt-get install findimagedupes"
    echo "  Arch: sudo pacman -S findimagedupes"
    echo "  Fedora: sudo dnf install findimagedupes"
    echo ""
    echo "Alternative: Using fdupes for exact duplicates only..."
    echo ""

    if command -v fdupes &> /dev/null; then
        echo "📊 Found fdupes - scanning for exact duplicates..."
        cd "$IMAGES_DIR" || exit 1
        fdupes -r -S .
        echo ""
        echo "To delete duplicates interactively, run:"
        echo "  cd $IMAGES_DIR && fdupes -r -d ."
    else
        echo "❌ Neither findimagedupes nor fdupes is installed!"
        echo ""
        echo "Install fdupes (for exact duplicates):"
        echo "  Ubuntu/Debian: sudo apt-get install fdupes"
        echo "  Arch: sudo pacman -S fdupes"
        echo "  Fedora: sudo dnf install fdupes"
    fi
    exit 1
fi

# Find duplicates using perceptual hashing (finds similar images)
echo "📊 Scanning for duplicate/similar images..."
cd "$IMAGES_DIR" || exit 1

findimagedupes -R . > /tmp/duplicates.txt 2>/dev/null

if [ -s /tmp/duplicates.txt ]; then
    echo "✅ Found duplicate groups:"
    echo ""
    cat /tmp/duplicates.txt
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "To delete duplicates interactively, run:"
    echo "  findimagedupes -R $IMAGES_DIR"
    echo ""
    echo "Or to delete with prompts:"
    echo "  findimagedupes -R -p $IMAGES_DIR"
else
    echo "✅ No duplicate images found!"
fi

rm -f /tmp/duplicates.txt
