#!/bin/bash

clear

# Set trap to catch errors
trap 'handle_error' ERR

# 1️⃣ Greeting
echo "🚀 Welcome to the Automated ETL Setup!"
echo "This script will set up your environment, deploy the infrastructure, and run your ETL pipeline."

# 2️⃣ Create & Write Environment Variables Dynamically
echo "🔹 Creating .env file..."

rm -f .env  # Remove existing .env

cat > .env <<EOL
AIRFLOW_POSTGRES_USER=airflow
AIRFLOW_POSTGRES_PASSWORD=airflow
AIRFLOW_DB=airflow
AIRFLOW_ADMIN_USER=admin
AIRFLOW_ADMIN_PASSWORD=admin
AIRFLOW_ADMIN_EMAIL=admin@example.com
AIRFLOW_DB_HOST=airflow_postgres

TFL_API_URL=https://api.tfl.gov.uk/AccidentStats
START_YEAR=2005
END_YEAR=2019

USE_CLOUD_DB=False
DB_HOST=postgres_db_tfl_accident_data
DB_PORT=5432
DB_NAME=tfl_accidents
DB_USER=admin
DB_PASSWORD=admin

GCS_CSV_PATH=processed_data/raw/csv/
DBT_PROFILES_DIR=/usr/app/dbt
DBT_PROJECT_NAME=tfl_accidents_project

LOCAL_STORAGE=/opt/airflow/processed_data/raw/csv
EOL

echo "✅ .env file created successfully."

# Create secrets folder for storing credentials
mkdir -p secrets

# 3️⃣ Authenticate with Google Cloud
echo "🔹 Please log in to your GCP account..."
gcloud auth login || { echo "❌ GCP login failed! Exiting..."; exit 1; }

# Get GCP project
GCP_PROJECT_ID=$(gcloud config get-value project)
echo "🔹 Using GCP project: $GCP_PROJECT_ID"
echo "GCP_PROJECT_ID=$GCP_PROJECT_ID" >> .env

# 4️⃣ Create Service Account for Storage
STORAGE_ADMIN_NAME="storage-admin"
STORAGE_ADMIN_EMAIL="$STORAGE_ADMIN_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com"
KEY_FILE_PATH="secrets/gcp_credentials.json"

# Check if Service Account exists
EXISTING_SA=$(gcloud iam service-accounts list --format="value(email)" --filter="email:$STORAGE_ADMIN_EMAIL")

if [ -z "$EXISTING_SA" ]; then
    echo "🔹 Creating new Storage Admin service account..."
    gcloud iam service-accounts create $STORAGE_ADMIN_NAME --display-name "Storage Admin Service Account"

    # Assign IAM roles
    echo "🔹 Assigning IAM roles..."
    for role in "roles/storage.admin" "roles/storage.objectAdmin"; do
        gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
            --member="serviceAccount:$STORAGE_ADMIN_EMAIL" --role="$role"
    done

    # Generate service account key
    echo "🔹 Generating service account key..."
    gcloud iam service-accounts keys create $KEY_FILE_PATH --iam-account=$STORAGE_ADMIN_EMAIL
    chmod 644 $KEY_FILE_PATH
else
    echo "✅ Service account already exists."
fi

# Store key path in .env
echo "GOOGLE_APPLICATION_CREDENTIALS=$KEY_FILE_PATH" >> .env

echo "✅ GCP authentication complete."

# 5️⃣ Deploy Infrastructure (Terraform)
echo "🔹 Deploying infrastructure with Terraform..."
cd terraform || { echo "❌ Terraform folder not found! Exiting..."; exit 1; }

terraform init
terraform apply -var="project_id=$GCP_PROJECT_ID" -auto-approve

# Get the created bucket name
DATALAKE_BUCKET_NAME="${GCP_PROJECT_ID}-datalake"
echo "GCS_BUCKET=$DATALAKE_BUCKET_NAME" >> ../.env
cd ..

echo "✅ Infrastructure setup complete."

# 6️⃣ Start Docker Services
echo "🔹 Starting Docker services..."
docker-compose up --build -d

# 7️⃣ Wait for Airflow
echo "⏳ Waiting for Airflow to initialize..."
sleep 20  # Adjust if needed

# 8️⃣ Trigger DAG and Monitor Progress
DAG_ID="end_to_end_pipeline"
echo "🔹 Unpausing and triggering DAG: $DAG_ID..."
docker exec -it airflow-webserver airflow dags unpause $DAG_ID
docker exec -it airflow-webserver airflow dags trigger $DAG_ID

echo "🔍 Monitoring DAG execution..."

MAX_RETRIES=50
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    STATUS=$(docker exec -it airflow-webserver airflow dags list-runs -d $DAG_ID --limit 1 --output json | jq -r '.[0].state')

    case "$STATUS" in
        "running")
            echo "⏳ DAG is still running... Checking again in 20 seconds."
            sleep 20
            ;;
        "success")
            echo "✅ DAG completed successfully!"
            break
            ;;
        "failed")
            echo "❌ DAG failed! Check Airflow logs for more details."
            exit 1
            ;;
        *)
            echo "⚠️ Unknown DAG status: $STATUS"
            exit 1
            ;;
    esac

    ((RETRY_COUNT++))
done

if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
    echo "⚠️ DAG did not complete within the expected time. Please check Airflow manually."
fi

# 9️⃣ Wait for Streamlit Dashboard
echo "🔹 Waiting for the Streamlit Dashboard to start..."
DASHBOARD_PORT=8501
RETRIES=20

for i in $(seq 1 $RETRIES); do
    if curl --silent --fail "http://localhost:$DASHBOARD_PORT" > /dev/null; then
        echo "✅ Streamlit Dashboard is now available!"
        break
    else
        echo "⏳ Streamlit Dashboard is still starting... Retrying in 10 seconds."
        sleep 10
    fi
done

# 🔟 Display URLs
AIRFLOW_DASHBOARD_URL="http://localhost:8082"
STREAMLIT_DASHBOARD_URL="http://localhost:$DASHBOARD_PORT"

sed -i "s|AIRFLOW_DASHBOARD_URL=.*|AIRFLOW_DASHBOARD_URL=$AIRFLOW_DASHBOARD_URL|g" .env

echo "✅ Setup Complete!"
echo "📊 Airflow Dashboard: $AIRFLOW_DASHBOARD_URL"
echo "📊 Streamlit Dashboard: $STREAMLIT_DASHBOARD_URL"
