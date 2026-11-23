#!/bin/bash
#
# Checks that analyzer.js finds the same codes as the Swift analyzer the apps
# and the Safari extension use, on every page text in cases.json.
# Needs node and the Swift compiler.
#
set -euo pipefail
cd "$(dirname "$0")"

root=../..
codes=$root/BillGuard/Resources/medical_codes.json
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp parity.swift "$work/main.swift"
swiftc -o "$work/parity" "$work/main.swift" \
    "$root"/BillGuardWebExtension/WebCaptureBridge.swift \
    "$root"/BillGuardShare/{BillCodeAnalyzer,MedicalBillModels,KnownProcedureCodes,PendingBillStore,CloudKitManager}.swift

# Both through one formatter, so only the content is compared.
format() { /usr/bin/python3 -c 'import json, sys; json.dump(json.load(sys.stdin), sys.stdout, indent=1, sort_keys=True)'; }
"$work/parity" . "$codes" | format > "$work/swift.json"
node parity.js "$codes" | format > "$work/js.json"

if diff -u "$work/swift.json" "$work/js.json"; then
    echo "Parity: Swift and JavaScript agree on $(node -e 'console.log(require("./cases.json").length)') pages."
else
    echo "Parity FAILED: the analyzers disagree (Swift on the left, JavaScript on the right)." >&2
    exit 1
fi
