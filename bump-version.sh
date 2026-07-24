#!/usr/bin/env bash
set -euo pipefail

PBXPROJ="HA Volume Control.xcodeproj/project.pbxproj"

# --- Read current values ---

current_marketing=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *//')
current_build=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *//;s/;//;s/ *//')
new_build=$((current_build + 1))

echo "Current version : $current_marketing (build $current_build)"
echo "New build number: $new_build"
echo ""

# --- Prompt for new marketing version ---

while true; do
    read -rp "New marketing version [$current_marketing]: " new_marketing
    new_marketing="${new_marketing:-$current_marketing}"

    # Validate that new version is greater than current using sort -V
    if [ "$new_marketing" = "$current_marketing" ]; then
        echo "Error: new version must be different from current version ($current_marketing)." >&2
        continue
    fi

    lower=$(printf '%s\n%s\n' "$current_marketing" "$new_marketing" | sort -V | head -1)
    if [ "$lower" != "$current_marketing" ]; then
        echo "Error: '$new_marketing' is not greater than '$current_marketing'." >&2
        continue
    fi

    break
done

echo ""
echo "Will update: $current_marketing (build $current_build) -> $new_marketing (build $new_build)"
read -rp "Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# --- Update pbxproj ---

sed -i '' \
    "s/MARKETING_VERSION = ${current_marketing};/MARKETING_VERSION = ${new_marketing};/g" \
    "$PBXPROJ"

sed -i '' \
    "s/CURRENT_PROJECT_VERSION = ${current_build};/CURRENT_PROJECT_VERSION = ${new_build};/g" \
    "$PBXPROJ"

echo "Updated $PBXPROJ"

# --- Commit, tag, push ---

git add "$PBXPROJ"
git commit -m "Bump version to $new_marketing"
git tag "v$new_marketing"
git push origin main
git push origin "v$new_marketing"

echo ""
echo "Done. Version $new_marketing (build $new_build) pushed and tagged as v$new_marketing."
