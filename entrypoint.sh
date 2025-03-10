#!/bin/bash
set -e  # Exit on error

clear
echo "🚀 Initializing the TFL Accidents ETL Setup Inside Debian-Host..."

# Define repo details
REPO_URL="https://github.com/Ruidozo/TFL-Accidents_05-19.git"
CLONE_DIR="/app/tfl-accidents"

# Ensure the repository is always up to date
if [ -d "$CLONE_DIR/.git" ]; then
    echo "🔹 Repository already exists. Pulling the latest changes..."
    cd "$CLONE_DIR"
    git reset --hard
    git pull origin main || { echo "❌ Failed to pull latest changes! Exiting..."; exit 1; }
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

echo "✅ Setup complete!"

# Start Airflow & Dashboard inside Debian-Host
echo "🔹 Starting Airflow and Streamlit inside Debian-Host..."
docker-compose up --build -d

echo "✅ Services started successfully! You can now access:"
echo "📊 Airflow UI: http://localhost:8082"
echo "📊 Streamlit Dashboard: http://localhost:8501"
