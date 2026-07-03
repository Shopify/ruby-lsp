#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VSIX_PATH="${EXT_DIR}/vscode-ruby-lsp.vsix"

SKIP_INSTALL=0
PRE_RELEASE=0

usage() {
  cat <<'EOF'
Build and install the local Ruby LSP VS Code extension.

Usage:
  ./scripts/install-local.sh [options]

Options:
  --skip-install   Skip "pnpm install"
  --pre-release    Build a pre-release VSIX
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --pre-release)
      PRE_RELEASE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm not found. Install/activate pnpm first:" >&2
  echo "  corepack enable" >&2
  echo "  corepack prepare pnpm@10.28.0 --activate" >&2
  exit 1
fi

if ! command -v code >/dev/null 2>&1; then
  echo "VS Code CLI 'code' not found in PATH." >&2
  echo "Run 'Shell Command: Install \"code\" command in PATH' from VS Code, then retry." >&2
  exit 1
fi

cd "${EXT_DIR}"

echo "==> Extension dir: ${EXT_DIR}"

if [[ ${SKIP_INSTALL} -eq 0 ]]; then
  echo "==> Installing dependencies"
  pnpm install
else
  echo "==> Skipping dependency install"
fi

echo "==> Compiling TypeScript"
pnpm run compile

echo "==> Packaging VSIX"
if [[ ${PRE_RELEASE} -eq 1 ]]; then
  pnpm run package_prerelease
else
  pnpm run package
fi

if [[ ! -f "${VSIX_PATH}" ]]; then
  echo "Expected VSIX not found at: ${VSIX_PATH}" >&2
  exit 1
fi

echo "==> Installing VSIX to local VS Code"
code --install-extension "${VSIX_PATH}" --force

echo "==> Done"
echo "Installed: ${VSIX_PATH}"
