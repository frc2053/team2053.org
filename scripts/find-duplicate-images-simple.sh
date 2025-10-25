#!/bin/bash

# Find duplicate images using MD5 checksums (exact duplicates)
# and file size comparison for potential near-duplicates

IMAGES_DIR="public/assets/images"

echo "🔍 Finding duplicate images in $IMAGES_DIR..."
echo ""

cd "$IMAGES_DIR" || exit 1

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EXACT DUPLICATES (same file content):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find exact duplicates using MD5 hash
declare -A checksums
duplicates_found=0

while IFS= read -r -d '' file; do
    # Get MD5 checksum
    checksum=$(md5sum "$file" | awk '{print $1}')

    if [[ -n "${checksums[$checksum]}" ]]; then
        if [[ $duplicates_found -eq 0 ]]; then
            echo "Group $(( (duplicates_found / 2) + 1 )):"
            echo "  ${checksums[$checksum]}"
        fi
        echo "  $file"
        duplicates_found=$((duplicates_found + 1))
        echo ""
    else
        checksums[$checksum]="$file"
    fi
done < <(find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) -print0)

if [[ $duplicates_found -eq 0 ]]; then
    echo "✅ No exact duplicates found!"
else
    echo "Found $duplicates_found duplicate files"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SIMILAR FILE SIZES (potential duplicates - manual review needed):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find files with very similar sizes (within 5% difference)
find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) -printf "%s %p\n" | sort -n > /tmp/image_sizes.txt

echo "Files grouped by similar size (±5%):"
echo ""

prev_size=0
prev_file=""
group_count=0

while read -r size file; do
    if [[ $prev_size -gt 0 ]]; then
        # Calculate 5% threshold
        threshold=$((prev_size * 5 / 100))
        diff=$((size - prev_size))
        diff=${diff#-}  # absolute value

        if [[ $diff -le $threshold ]] && [[ $diff -gt 0 ]]; then
            if [[ $group_count -eq 0 ]]; then
                echo "Similar size group:"
                echo "  $prev_file ($(numfmt --to=iec-i --suffix=B $prev_size))"
                group_count=$((group_count + 1))
            fi
            echo "  $file ($(numfmt --to=iec-i --suffix=B $size))"
            group_count=$((group_count + 1))
        else
            if [[ $group_count -gt 0 ]]; then
                echo ""
                group_count=0
            fi
        fi
    fi
    prev_size=$size
    prev_file="$file"
done < /tmp/image_sizes.txt

rm -f /tmp/image_sizes.txt

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SAME FILENAME (different paths):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Find files with same basename in different locations
find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) -printf "%f\t%p\n" | sort | uniq -w 30 -D

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To manually delete duplicates, review the above list and run:"
echo "  rm \"$IMAGES_DIR/path/to/duplicate.jpg\""
echo ""
echo "For better fuzzy duplicate detection, install:"
echo "  sudo pacman -S findimagedupes"
echo "Then run:"
echo "  ./scripts/find-duplicate-images.sh"
