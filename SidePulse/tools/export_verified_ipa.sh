#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <archive.xcarchive> <export-directory> <ExportOptions.plist>" >&2
    exit 2
fi

archive_path=$1
export_directory=$2
export_options=$3
script_directory=$(cd "$(dirname "$0")" && pwd)

/usr/bin/xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_directory" \
    -exportOptionsPlist "$export_options"

shopt -s nullglob
exported_ipas=("$export_directory"/*.ipa)
if [[ ${#exported_ipas[@]} -eq 0 ]]; then
    echo "Export completed without an IPA in $export_directory" >&2
    exit 1
fi

for ipa in "${exported_ipas[@]}"; do
    "$script_directory/verify_signed_apns_environment.sh" "$ipa"
done
