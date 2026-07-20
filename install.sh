#!/usr/bin/env bash

set -euo pipefail

APP_NAME="sd-deploy"
VERSION="v1.0.0-beta" # Change this as you release new versions
GITHUB_REPO="IsaiahTek/SafeDeployer" # Update to your actual repository
INSTALL_DIR="/usr/local/bin"
USE_SUDO=true

if [ "${1:-}" == "--local" ]; then
    INSTALL_DIR="$HOME/.local/bin"
    USE_SUDO=false
fi

echo "Starting installation for SafeDeployer..."

# --- Step 1: Detect OS and Architecture ---
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "Error: Unsupported architecture ($ARCH)"
        exit 1
        ;;
esac

case "$OS" in
    linux|darwin) ;;
    *)
        echo "Error: Unsupported operating system ($OS)"
        exit 1
        ;;
esac

# Formulate binary name based on cross-compilation outputs
BINARY_NAME="${APP_NAME}-${OS}-${ARCH}"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${BINARY_NAME}"

# --- Step 2: Download Pre-compiled Binary ---
echo "Downloading pre-compiled binary for ${OS}/${ARCH}..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if command -v curl &> /dev/null; then
    curl -Lsf "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME"
elif command -v wget &> /dev/null; then
    wget -qO "$TMP_DIR/$APP_NAME" "$DOWNLOAD_URL"
else
    echo "Error: Neither curl nor wget was found. Please install one to download the binary."
    exit 1
fi

# --- Step 3: Move to Path ---
echo " Installing binary to $INSTALL_DIR..."
if [ ! -d "$INSTALL_DIR" ]; then
    if [ "$USE_SUDO" = true ]; then sudo mkdir -p "$INSTALL_DIR"; else mkdir -p "$INSTALL_DIR"; fi
fi

if [ "$USE_SUDO" = true ]; then
    sudo mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
    sudo chmod +x "$INSTALL_DIR/$APP_NAME"
else
    mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
    chmod +x "$INSTALL_DIR/$APP_NAME"
fi

# --- Step 4: Verify and Handle PATH (Same as before) ---
if ! command -v "$APP_NAME" &> /dev/null; then
    SHELL_PROFILE=""
    case "$SHELL" in
        */bash) [ -f "$HOME/.bashrc" ] && SHELL_PROFILE="$HOME/.bashrc" || SHELL_PROFILE="$HOME/.bash_profile" ;;
        */zsh) SHELL_PROFILE="$HOME/.zshrc" ;;
        */fish) SHELL_PROFILE="$HOME/.config/fish/config.fish" ;;
        *) SHELL_PROFILE="$HOME/.profile" ;;
    esac

    if [ -n "$SHELL_PROFILE" ] && [ -f "$SHELL_PROFILE" ]; then
        echo "Appending $INSTALL_DIR to PATH in $SHELL_PROFILE..."
        if [[ "$SHELL_PROFILE" == *"fish"* ]]; then
            echo "fish_add_path $INSTALL_DIR" >> "$SHELL_PROFILE"
        else
            echo -e "\n# SafeDeployer PATH\nexport PATH=\"\$PATH:$INSTALL_DIR\"" >> "$SHELL_PROFILE"
        fi
        echo "Please run: source $SHELL_PROFILE"
    fi
fi

echo "SafeDeployer installation complete!"