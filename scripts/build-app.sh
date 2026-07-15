#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist}"
ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-}"
APP_PATH="${DIST_DIR}/AgentPulse.app"
INFO_TEMPLATE="${ROOT_DIR}/Resources/Info.plist"
ICON_SOURCE="${ROOT_DIR}/Resources/AppIcon.png"

if [[ " ${ARCHS} " == *" arm64 "* && " ${ARCHS} " == *" x86_64 "* ]]; then
    ARCH_LABEL="macos-universal"
else
    ARCH_LABEL="macos-${ARCHS// /-}"
fi
ZIP_PATH="${DIST_DIR}/AgentPulse-${VERSION}-${ARCH_LABEL}${ARTIFACT_SUFFIX}.zip"

arch_args=()
for arch in ${ARCHS}; do
    arch_args+=(--arch "${arch}")
done

mkdir -p "${DIST_DIR}"
rm -rf "${APP_PATH}"
rm -f "${ZIP_PATH}" "${ZIP_PATH}.sha256"

echo "Building AgentPulse ${VERSION} (${ARCHS})"
swift build --package-path "${ROOT_DIR}" -c release "${arch_args[@]}"
BIN_DIR="$(swift build --package-path "${ROOT_DIR}" -c release "${arch_args[@]}" --show-bin-path)"

mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources/Scripts"
install -m 755 "${BIN_DIR}/AgentPulse" "${APP_PATH}/Contents/MacOS/AgentPulse"
install -m 644 "${INFO_TEMPLATE}" "${APP_PATH}/Contents/Info.plist"
install -m 755 "${ROOT_DIR}/scripts/agent-pulse-codex-hook.mjs" "${APP_PATH}/Contents/Resources/Scripts/"
install -m 755 "${ROOT_DIR}/scripts/agentpulse-hook.py" "${APP_PATH}/Contents/Resources/Scripts/"

plutil -replace CFBundleShortVersionString -string "${VERSION}" "${APP_PATH}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${BUILD_NUMBER}" "${APP_PATH}/Contents/Info.plist"

SPARKLE_FRAMEWORK="${BIN_DIR}/Sparkle.framework"
if [[ ! -d "${SPARKLE_FRAMEWORK}" ]]; then
    echo "Sparkle.framework was not produced by SwiftPM" >&2
    exit 1
fi
mkdir -p "${APP_PATH}/Contents/Frameworks"
ditto "${SPARKLE_FRAMEWORK}" "${APP_PATH}/Contents/Frameworks/Sparkle.framework"

if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    plutil -insert SUFeedURL -string \
        "https://github.com/xiaoaozz/AgentPulse/releases/latest/download/appcast.xml" \
        "${APP_PATH}/Contents/Info.plist"
    plutil -insert SUPublicEDKey -string "${SPARKLE_PUBLIC_KEY}" "${APP_PATH}/Contents/Info.plist"
else
    plutil -remove SUEnableAutomaticChecks "${APP_PATH}/Contents/Info.plist"
    plutil -remove SUAllowsAutomaticUpdates "${APP_PATH}/Contents/Info.plist"
fi

ICON_WORK_DIR="$(mktemp -d "${DIST_DIR}/AgentPulse-icons.XXXXXX")"
ICONSET_DIR="${ICON_WORK_DIR}/AgentPulse.iconset"
mkdir -p "${ICONSET_DIR}"
cleanup() {
    rm -rf "${ICON_WORK_DIR}"
}
trap cleanup EXIT

make_icon() {
    local pixels="$1"
    local filename="$2"
    sips -z "${pixels}" "${pixels}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/${filename}" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "${ICONSET_DIR}" -o "${APP_PATH}/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "Signing with Developer ID identity"
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" \
        "${APP_PATH}/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP_PATH}"
else
    echo "No SIGN_IDENTITY configured; applying an ad-hoc signature"
    # Hardened Runtime library validation requires a real shared Team ID.
    # Ad-hoc builds have none, so enabling it would prevent the executable
    # from loading the embedded Sparkle framework.
    codesign --force --deep --sign - "${APP_PATH}"
fi

create_zip() {
    rm -f "${ZIP_PATH}"
    ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
}

create_zip

if [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Submitting with notarytool keychain profile"
    xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${APP_PATH}"
    create_zip
elif [[ -n "${SIGN_IDENTITY:-}" && -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    echo "Submitting with App Store Connect API key"
    xcrun notarytool submit "${ZIP_PATH}" \
        --key "${NOTARY_KEY_PATH}" \
        --key-id "${NOTARY_KEY_ID}" \
        --issuer "${NOTARY_ISSUER_ID}" \
        --wait
    xcrun stapler staple "${APP_PATH}"
    create_zip
fi

(
    cd "${DIST_DIR}"
    shasum -a 256 "$(basename "${ZIP_PATH}")" > "$(basename "${ZIP_PATH}").sha256"
)

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
echo "Created ${ZIP_PATH}"
