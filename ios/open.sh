#!/bin/sh
# Generates the Xcode project from project.yml and opens it.
set -e
cd "$(dirname "$0")"
command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen
open BRB.xcodeproj
