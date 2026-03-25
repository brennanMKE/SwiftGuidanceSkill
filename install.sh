#!/bin/zsh

set -e

# Configuration
SKILLS_DIR="${HOME}/.claude/skills"
SKILL_NAME="swift-guidance"
SKILL_PATH="${SKILLS_DIR}/${SKILL_NAME}"
REPO_NAME="SwiftGuidanceSkill"
REPO_URL="${REPO_URL:-https://github.com/brennanMKE/${REPO_NAME}.git}"
SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Installing ${SKILL_NAME} skill...${NC}"

# Create skills directory if it doesn't exist
if [[ ! -d "${SKILLS_DIR}" ]]; then
    echo "Creating ${SKILLS_DIR}..."
    mkdir -p "${SKILLS_DIR}"
fi

# Check if skill already exists
if [[ -d "${SKILL_PATH}" ]]; then
    echo -e "${GREEN}✓${NC} ${SKILL_NAME} skill already installed at ${SKILL_PATH}"
    read -k 1 "?Replace with files from this repo? [Y/n] " REPLACE
    echo ""
    case "${REPLACE}" in
        y|Y|"")
            echo "Removing old installation..."
            rm -rf "${SKILL_PATH}"
            ;;
        n|N)
            echo "Installation cancelled."
            exit 0
            ;;
        *)
            echo -e "${RED}✗${NC} Invalid input. Please enter Y or n."
            exit 1
            ;;
    esac
fi

# Install from local directory or git repo
if [[ -d "${SCRIPT_DIR}/${SKILL_NAME}" ]]; then
    # Install from local directory
    echo "Installing from local directory..."
    ln -s "${SCRIPT_DIR}/${SKILL_NAME}" "${SKILL_PATH}"
    echo -e "${GREEN}✓${NC} ${SKILL_NAME} skill installed successfully"
else
    # Clone from git repo
    echo "Installing from git repository..."
    git clone "${REPO_URL}" "${SKILL_PATH}" 2>/dev/null || {
        echo -e "${RED}✗${NC} Failed to clone repository from ${REPO_URL}"
        echo "Please set REPO_URL environment variable or run from the repo directory"
        exit 1
    }
    echo -e "${GREEN}✓${NC} ${SKILL_NAME} skill installed successfully"
fi

echo ""
echo "Skill is now available in Claude Code!"
