#!/bin/bash

clear

# 1️⃣ Greeting
echo "🚀 Welcome to the Automated ETL Setup!"
echo "This script will set up your environment, deploy the infrastructure, and run your ETL pipeline."

# 2️⃣ Create & Write Environment
cat > .env <<EOL
AIRFLOW_POSTGRES_USER=airflow
AIRFLOW_POSTGRES_PASSWORD=airflow
AIRFLOW_DB=airflow
AIRFLOW_ADMIN_USER=admin
AIRFLOW_ADMIN_PASSWORD=admin
AIRFLOW_ADMIN_EMAIL=admin@example.com

TFL_API_URL=https://api.tfl.gov.uk/AccidentStats
START_YEAR=2005
END_YEAR=2019

USE_CLOUD_DB=False
DB_HOST=postgres_db_tfl_accident_data
DB_PORT=5432
DB_NAME=tfl_accidents
DB_USER=admin
DB_PASSWORD=admin

POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=tfl_accidents

KAGGLE_DATASET=zongaobian/london-weather-data-from-1979-to-2023
GCS_CSV_PATH=processed_data/raw/csv/
DBT_PROFILES_DIR=/usr/app/dbt
DBT_PROJECT_NAME=tfl_accidents_project

LOCAL_STORAGE=/opt/airflow/processed_data/raw/csv
EOL

# 3️⃣ Install dependencies
apt-get update

if ! command -v gcloud &> /dev/null; then
  curl -sSL https://sdk.cloud.google.com | bash
  exec -l $SHELL
  gcloud components install gke-gcloud-auth-plugin
fi

if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
fi

if ! command -v docker-compose &> /dev/null; then
  sudo apt install -y docker-compose
fi

# GCP Authentication
gcloud auth login
USER_EMAIL=$(gcloud config get-value account)
echo "Logged in as: $USER_EMAIL"

# Project Selection
PROJECTS=$(gcloud projects list --format="table(projectId, name)")
echo "$PROJECTS"

read -p "Enter your GCP project ID (existing or new): " GCP_PROJECT_ID
if ! gcloud projects describe $GCP_PROJECT_ID &> /dev/null; then
  gcloud projects create $GCP_PROJECT_ID --set-as-default
fi

gcloud config set project $GCP_PROJECT_ID

# Service Account setup
SERVICE_ACCOUNT_NAME="storage-admin"
SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com"
KEY_FILE_PATH="secrets/gcp_credentials.json"

mkdir -p secrets
rm -f $KEY_FILE_PATH

gcloud iam service-accounts create storage-admin --display-name="Storage Admin"
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" --role="roles/storage.admin"
gcloud iam service-accounts keys create $KEY_FILE_PATH --iam-account=$SERVICE_ACCOUNT_EMAIL

# Set permissions
chmod 644 $KEY_FILE_PATH

# Update bucket name
GCS_BUCKET="$GCP_PROJECT_ID-datalake"
echo "GCS_BUCKET=$GCS_BUCKET" >> .env

echo "LOCAL_STORAGE=/opt/airflow/processed_data/raw/csv" >> .env

# Docker compose setup
if [ -f docker-compose.yaml ]; then
  docker-compose up -d
else
  echo "docker-compose.yaml not found! Exiting..."
  exit 1
fi

# Wait and trigger Airflow DAG
sleep 20

docker exec airflow_webserver-tfl airflow dags unpause end_to_end_pipeline
docker exec airflow_webserver-tfl airflow dags trigger end_to_end_pipeline

# Real-time Airflow logs monitoring
AIRFLOW_CONTAINER=$(docker ps --format "{{.Names}}" | grep airflow_webserver)

echo "🔍 Showing real-time Airflow logs (Press Ctrl+C to exit):"
docker exec -it $AIRFLOW_CONTAINER airflow dags trigger end_to_end_pipeline

docker logs -f $AIRFLOW_CONTAINER 2>&1 | tee airflow_realtime.log

# URLs
AIRFLOW_DASHBOARD_URL="http://localhost:8082"
STREAMLIT_DASHBOARD_URL="http://localhost:8501"

echo "✅ Setup Complete!"
echo "🔗 Airflow: $AIRFLOW_DASHBOARD_URL"
echo "🔗 Streamlit: $STREAMLIT_DASHBOARD_URL"
