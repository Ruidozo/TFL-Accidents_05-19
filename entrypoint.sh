#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

clear
echo "🚀 Initializing the TFL Accidents ETL Setup..."

# Define repository details
REPO_URL="https://github.com/ruidozo/tfl-accidents.git"
CLONE_DIR="/app/tfl-accidents"

# Ensure /app is clean
rm -rf $CLONE_DIR

echo "🔹 Cloning the repository..."
git clone $REPO_URL $CLONE_DIR || { echo "❌ Failed to clone repository! Exiting..."; exit 1; }

# Navigate into the cloned project directory
cd $CLONE_DIR || { echo "❌ Failed to enter project directory! Exiting..."; exit 1; }

echo "✅ Repository cloned successfully."

# Ensure `setup.sh` is executable
chmod +x setup.sh

echo "🔹 Running setup.sh..."
./setup.sh || { echo "❌ Setup script failed! Exiting..."; exit 1; }

echo "✅ Container setup complete!"
