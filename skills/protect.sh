#!/bin/sh
# Write-protect the frozen decwar skill in this directory.
cd "$(dirname "$0")" || exit 1
chmod -R -w .
echo "skills are write-protected"
