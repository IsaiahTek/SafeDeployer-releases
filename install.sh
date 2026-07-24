#!/usr/bin/env bash

set -euo pipefail

APP_NAME="sd-deploy"
VERSION="${VERSION:-v1.0.0-test}" # Target tag on GitHub releases
GITHUB_REPO="IsaiahTek/SafeDeployer-releases" # Update to your actual repository
INSTALL_DIR="/usr/local/bin"
USE_SUDO=false

if [ "${1:-}" == "--local" ]; then
    INSTALL_DIR="$HOME/.local/bin"
    USE_SUDO=false
elif [ "$(id -u)" -eq 0 ] || [ -w "$INSTALL_DIR" ]; then
    USE_SUDO=false
elif sudo -n true 2>/dev/null; then
    USE_SUDO=true
elif command -v sudo &> /dev/null && [ -t 0 ]; then
    USE_SUDO=true
else
    # Non-interactive shell without passwordless sudo: fallback to user home directory
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
    if ! curl -Lsf "$DOWNLOAD_URL" -o "$TMP_DIR/$APP_NAME"; then
        echo "Error: Failed to download binary from $DOWNLOAD_URL"
        echo "   Release version '$VERSION' for asset '$BINARY_NAME' was not found."
        exit 1
    fi
elif command -v wget &> /dev/null; then
    if ! wget -qO "$TMP_DIR/$APP_NAME" "$DOWNLOAD_URL"; then
        echo "Error: Failed to download binary from $DOWNLOAD_URL"
        echo "   Release version '$VERSION' for asset '$BINARY_NAME' was not found."
        exit 1
    fi
else
    echo "Error: Neither curl nor wget was found. Please install one to download the binary."
    exit 1
fi

# --- Step 3: Move to Path ---
echo " Installing binary to $INSTALL_DIR..."

INSTALLED=false
if [ "$USE_SUDO" = true ]; then
    if sudo mkdir -p "$INSTALL_DIR" 2>/dev/null && sudo mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME" 2>/dev/null; then
        sudo chmod +x "$INSTALL_DIR/$APP_NAME"
        INSTALLED=true
    else
        echo " Could not write to $INSTALL_DIR with sudo. Falling back to user directory..."
        INSTALL_DIR="$HOME/.local/bin"
    fi
fi

if [ "$INSTALLED" = false ]; then
    if mkdir -p "$INSTALL_DIR" 2>/dev/null && mv "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME" 2>/dev/null && chmod +x "$INSTALL_DIR/$APP_NAME" 2>/dev/null; then
        INSTALLED=true
    else
        # Tier 3: /tmp emergency fallback
        EMERGENCY_DIR="/tmp"
        if mv "$TMP_DIR/$APP_NAME" "$EMERGENCY_DIR/$APP_NAME" 2>/dev/null && chmod +x "$EMERGENCY_DIR/$APP_NAME" 2>/dev/null; then
            INSTALL_DIR="$EMERGENCY_DIR"
            INSTALLED=true
            echo " Warning: Installed binary to temporary path $INSTALL_DIR/sd-deploy as emergency fallback."
        else
            echo " Error: Failed to install SafeDeployer binary."
            echo "   Could not write to /usr/local/bin, $HOME/.local/bin, or /tmp."
            echo "   Please check filesystem write permissions and available disk space."
            exit 1
        fi
    fi
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