#!/bin/bash

# Script to set up and push the AutoGrowingLPToken project to GitHub
# Make sure to run this script from the project root directory

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Git repository for AutoGrowingLPToken...${NC}"

# Initialize Git repository if not already initialized
if [ ! -d .git ]; then
  echo -e "${GREEN}Initializing Git repository...${NC}"
  git init
else
  echo -e "${GREEN}Git repository already initialized.${NC}"
fi

# Add all files to Git
echo -e "${GREEN}Adding files to Git...${NC}"
git add .

# Create initial commit
echo -e "${GREEN}Creating initial commit...${NC}"
git commit -m "Initial commit: AutoGrowingLPToken with Base Sepolia deployment"

echo -e "${YELLOW}Repository is ready for GitHub!${NC}"
echo -e "${YELLOW}To push to GitHub, follow these steps:${NC}"
echo -e "1. Create a new repository on GitHub (without README, .gitignore, or license)"
echo -e "2. Run the following commands:"
echo -e "   git remote add origin https://github.com/YOUR_USERNAME/AutoGrowingLPToken.git"
echo -e "   git branch -M main"
echo -e "   git push -u origin main"

echo -e "${GREEN}Done!${NC}"
