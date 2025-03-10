#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

clear
echo "🚀 Initializing the TFL Accidents ETL Setup..."

# Define repository details
REPO_URL="https://github.com/Ruidozo/TFL-Accidents_05-19.git"
CLONE_DIR="/app/tfl-accidents"

# Check if the repo already exists
if [ -d "$CLONE_DIR/.git" ]; then
    echo "🔹 Repository already exists. Pulling the latest changes..."
    cd "$CLONE_DIR"
    git reset --hard
    git pull origin main || { echo "❌ Failed to pull the latest changes! Exiting..."; exit 1; }
else
    echo "🔹 Cloning the repository for the first time..."
    rm -rf "$CLONE_DIR"
    git clone "$REPO_URL" "$CLONE_DIR" || { echo "❌ Failed to clone repository! Exiting..."; exit 1; }
fi

# Navigate into the cloned project directory
cd "$CLONE_DIR" || { echo "❌ Failed to enter project directory! Exiting..."; exit 1; }

echo "✅ Repository is up to date."

# Ensure `setup.sh` is executable
chmod +x setup.sh

echo "🔹 Running setup.sh..."
./setup.sh || { echo "❌ Setup script failed! Exiting..."; exit 1; }

echo "✅ Container setup complete!"
