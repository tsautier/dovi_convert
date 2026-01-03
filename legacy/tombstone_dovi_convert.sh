#!/usr/bin/env bash
# =============================================================================
# dovi_convert - Migration Notice
# =============================================================================
#
# This script is a placeholder. The Bash version has been replaced by Python.
#
# =============================================================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[1;33m"
BOLD="\033[1m"
RESET="\033[0m"

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗"
echo -e "║          dovi_convert v7.0.0 - MAJOR UPDATE                   ║"
echo -e "╠══════════════════════════════════════════════════════════════╣"
echo -e "║                                                              ║"
echo -e "║  ${BOLD}Python is now required.${RESET}${YELLOW}                                     ║"
echo -e "║                                                              ║"
echo -e "║  The Bash version has been retired. v7+ is a complete       ║"
echo -e "║  Python rewrite with improved performance and fewer deps.   ║"
echo -e "║                                                              ║"
echo -e "╠══════════════════════════════════════════════════════════════╣"
echo -e "║  ${BOLD}To upgrade:${RESET}${YELLOW}                                                  ║"
echo -e "║                                                              ║"
echo -e "║  1. Ensure Python 3.8+ is installed                         ║"
echo -e "║  2. Download dovi_convert.py from the GitHub releases       ║"
echo -e "║  3. Replace your existing dovi_convert with the new .py     ║"
echo -e "║                                                              ║"
echo -e "║  ${BOLD}https://github.com/cryptochrome/dovi_convert/releases${RESET}${YELLOW}       ║"
echo -e "║                                                              ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Check if Python 3 is available
if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 --version 2>&1)
    echo -e "${GREEN}✓ Python detected: $PY_VERSION${RESET}"
    echo "  You're ready to use the new version."
else
    echo -e "${RED}✗ Python 3 not found.${RESET}"
    echo "  Please install Python 3.8+ before upgrading."
fi

echo ""
exit 1
