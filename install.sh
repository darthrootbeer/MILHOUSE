#!/bin/bash
# Milhouse: installer
#
# Goal: install Milhouse into a target project with a single command.
#
# Typical usage (from inside this repo):
#   ./install.sh
#   ./install.sh --target /path/to/your-project
#
# Intended usage (from a cloned temp copy):
#   ./install.sh --target "$ORIGINAL_PROJECT_DIR"
#
# Notes:
# - This installer is intentionally minimal: it installs `scripts/milhouse.sh`
#   and ensures `.milhouse/` is gitignored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_MILHOUSE_SH="$SCRIPT_DIR/scripts/milhouse.sh"

TARGET_DIR="$(pwd)"
FORCE="0"
YES="0"
INSTALL_GUM="${INSTALL_GUM:-0}"
INSTALL_CURSOR_AGENT="${INSTALL_CURSOR_AGENT:-0}"

usage() {
  cat <<'EOF'
Milhouse installer

USAGE
  ./install.sh [--target PATH] [--force] [--yes] [--install-gum] [--install-cursor-agent] [--help]

OPTIONS
  --target PATH   Install into PATH (default: current directory)
  --force         Overwrite existing scripts/milhouse.sh if present
  --yes           Auto-install recommended tools (where possible)
  --install-gum   Install gum if missing (Homebrew on macOS, apt/dnf on Linux)
  --install-cursor-agent
                  Install cursor-agent if missing (requires npm)
  --help          Show this help

WHAT IT DOES
  - Installs Milhouse runner to: scripts/milhouse.sh
  - Ensures .gitignore contains: .milhouse/

RECOMMENDED TOOLS
  - gum (optional): nicer menus and output formatting
  - cursor-agent (required to actually run iterations)
EOF
}

has_tty() {
  [[ -t 0 ]] && [[ -r /dev/tty ]]
}

prompt_confirm() {
  local prompt="$1"
  local default_no="${2:-1}" # 1 => default No, 0 => default Yes

  if [[ "$YES" == "1" ]]; then
    return 0
  fi

  if has_tty; then
    if [[ "$default_no" == "1" ]]; then
      read -r -p "$prompt [y/N] " reply < /dev/tty
    else
      read -r -p "$prompt [Y/n] " reply < /dev/tty
    fi
    [[ "${reply:-}" =~ ^[Yy]$ ]]
    return $?
  fi

  # No TTY (e.g., curl | bash). Be safe: default to "No".
  return 1
}

install_gum() {
  if command -v gum >/dev/null 2>&1; then
    return 0
  fi

  echo "gum not found (optional, improves the UI)."

  if [[ "$INSTALL_GUM" == "1" ]] || [[ "$YES" == "1" ]]; then
    echo "Installing gum..."
  else
    if ! prompt_confirm "Install gum?" 1; then
      echo "Skip: gum not installed."
      return 0
    fi
  fi

  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install gum
      return 0
    fi
    echo "Could not install gum automatically: Homebrew not found."
    echo "Install Homebrew first, then run: brew install gum"
    return 0
  fi

  if [[ -f /etc/debian_version ]]; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
    sudo apt update
    sudo apt install -y gum
    return 0
  fi

  if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
    cat <<'EOF' | sudo tee /etc/yum.repos.d/charm.repo >/dev/null
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF
    sudo dnf install -y gum
    return 0
  fi

  echo "Could not auto-install gum for this system."
  echo "Install instructions: https://github.com/charmbracelet/gum#installation"
  return 0
}

install_cursor_agent() {
  if command -v cursor-agent >/dev/null 2>&1; then
    return 0
  fi

  echo "cursor-agent not found (required to run Milhouse iterations)."

  if [[ "$INSTALL_CURSOR_AGENT" == "1" ]] || [[ "$YES" == "1" ]]; then
    echo "Installing cursor-agent..."
  else
    if ! prompt_confirm "Install cursor-agent now (requires npm)?" 1; then
      echo "Skip: cursor-agent not installed."
      echo "Later, you can install it with:"
      echo "  npm install -g cursor-agent"
      return 0
    fi
  fi

  if command -v npm >/dev/null 2>&1; then
    npm install -g cursor-agent
    return 0
  fi

  echo "Could not install cursor-agent automatically: npm not found."
  echo "Install Node.js/npm, then run: npm install -g cursor-agent"
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    --yes|-y)
      YES="1"
      shift
      ;;
    --install-gum)
      INSTALL_GUM="1"
      shift
      ;;
    --install-cursor-agent)
      INSTALL_CURSOR_AGENT="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: --target requires a PATH" >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_MILHOUSE_SH" ]]; then
  echo "Error: could not find source script: $SOURCE_MILHOUSE_SH" >&2
  echo "Fix: run this installer from the Milhouse repo root." >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════════"
echo "Milhouse installer"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Target: $TARGET_DIR"
echo ""

# Optional dependency installs (safe + opt-in)
install_gum
install_cursor_agent

# Ensure target has scripts/ directory
mkdir -p "$TARGET_DIR/scripts"

TARGET_MILHOUSE_SH="$TARGET_DIR/scripts/milhouse.sh"

if [[ -f "$TARGET_MILHOUSE_SH" ]] && [[ "$FORCE" != "1" ]]; then
  echo "Already installed: scripts/milhouse.sh exists"
  echo "Skip: not overwriting (use --force to overwrite)"
else
  if [[ -f "$TARGET_MILHOUSE_SH" ]] && [[ "$FORCE" == "1" ]]; then
    cp "$TARGET_MILHOUSE_SH" "$TARGET_MILHOUSE_SH.bak.$(date +%Y%m%d-%H%M%S)" || true
  fi
  cp "$SOURCE_MILHOUSE_SH" "$TARGET_MILHOUSE_SH"
  chmod +x "$TARGET_MILHOUSE_SH"
  echo "✓ Installed: scripts/milhouse.sh"
fi

# Ensure .gitignore contains .milhouse/
GITIGNORE="$TARGET_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if grep -qE '^[[:space:]]*\.milhouse/([[:space:]]*)$' "$GITIGNORE" 2>/dev/null; then
    echo "✓ .gitignore already ignores .milhouse/"
  else
    {
      echo ""
      echo "# Milhouse (state created at runtime)"
      echo ".milhouse/"
    } >> "$GITIGNORE"
    echo "✓ Updated .gitignore (added .milhouse/)"
  fi
else
  cat > "$GITIGNORE" <<'EOF'
# Milhouse (state created at runtime)
.milhouse/
EOF
  echo "✓ Created .gitignore (added .milhouse/)"
fi

echo ""
echo "Next:"
echo "  Run: ./scripts/milhouse.sh"
echo ""
