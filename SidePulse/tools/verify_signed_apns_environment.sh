#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <exported .app or .ipa>" >&2
    exit 2
fi

artifact=$1
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

if [[ "$artifact" == *.ipa ]]; then
    /usr/bin/unzip -q "$artifact" -d "$temporary_directory"
    app_path=$(find "$temporary_directory/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)
elif [[ "$artifact" == *.app ]]; then
    app_path=$artifact
else
    echo "Expected an exported .app or .ipa: $artifact" >&2
    exit 2
fi

if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
    echo "No app bundle found in $artifact" >&2
    exit 1
fi

info_plist="$app_path/Info.plist"
signed_entitlements="$temporary_directory/signed-entitlements.plist"
/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/codesign -d --entitlements :- "$app_path" > "$signed_entitlements" 2>/dev/null

configured=$(/usr/libexec/PlistBuddy -c 'Print :SidePulseAPNSEnvironment' "$info_plist")
signed=$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$signed_entitlements")

case "$configured" in
    development|production) ;;
    *) echo "Invalid or missing SidePulseAPNSEnvironment in exported app: $configured" >&2; exit 1 ;;
esac

if [[ "$configured" != "$signed" ]]; then
    echo "APNs environment mismatch: app is configured for '$configured' but signed for '$signed'." >&2
    exit 1
fi

echo "Verified signed APNs environment: $configured"
