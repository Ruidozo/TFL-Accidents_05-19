#!/bin/bash

clear


# Set trap to catch errors and run handle_error function
trap 'handle_error' ERR

# 1️⃣ Greeting
echo "🚀 Welcome to the Automated ETL Setup!"
echo "This script will set up your environment, deploy the infrastructure, and run your ETL pipeline."

# 2️⃣ Create & Write Environment Variables Dynamically
echo "🔹 Creating and writing to .env file..."

# Remove existing .env to start fresh
rm -f .env

# Create & Write Environment
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

# 3️⃣ Install Google Cloud SDK, Docker, Docker Compose, and Terraform
echo "🔹 Installing dependencies..."

# Install Google Cloud SDK if not installed
if ! command -v gcloud &> /dev/null; then
  echo "🔸 Installing Google Cloud SDK..."
  curl -sSL https://sdk.cloud.google.com | bash
  exec -l $SHELL
  gcloud components install gke-gcloud-auth-plugin --quiet
fi

# Install Docker if not installed
if ! command -v docker &> /dev/null; then
  echo "🔸 Installing Docker..."
  sudo apt update -y && sudo apt install -y docker.io
  sudo systemctl enable --now docker
fi

# Install Docker Compose if not installed
if ! command -v docker-compose &> /dev/null; then
  echo "🔸 Installing Docker Compose..."
  sudo apt install -y docker-compose
fi

# Install Terraform if not installed
if ! command -v terraform &> /dev/null; then
  echo "🔸 Installing Terraform..."
  sudo apt install -y unzip
  TERRAFORM_VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep "tag_name" | cut -d: -f2 | tr -d ',"v')
  wget https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_"$TERRAFORM_VERSION"_linux_amd64.zip
  unzip terraform_"$TERRAFORM_VERSION"_linux_amd64.zip
  sudo mv terraform /usr/local/bin/
  rm terraform_"$TERRAFORM_VERSION"_linux_amd64.zip
fi

# 4️⃣ Ask User to Authenticate with Google Cloud
echo "🔹 Please log in to your GCP account..."
gcloud auth login || { echo "❌ GCP login failed! Exiting..."; exit 1; }

# Get the authenticated user's email
USER_EMAIL=$(gcloud config get-value account)
echo "🔹 You are logged in as: $USER_EMAIL"

# Fetch available GCP projects
echo "🔹 Fetching available GCP projects..."
gcloud projects list --format="table(projectId, name)" 

while true; do
  read -p "Enter an existing GCP Project ID (or press Enter to create a new one): " GCP_PROJECT_ID

  if [ -z "$GCP_PROJECT_ID" ]; then
    read -p "Enter a new GCP Project ID: " GCP_PROJECT_ID
    echo "🔹 Creating new project: $GCP_PROJECT_ID..."
    
    # Attempt to create the project
    gcloud projects create $GCP_PROJECT_ID --name="$GCP_PROJECT_ID" --set-as-default
    
    # Verify project creation
    PROJECT_EXISTS=$(gcloud projects describe $GCP_PROJECT_ID --format="value(projectId)" 2>/dev/null)
    if [ -z "$PROJECT_EXISTS" ]; then
      echo "❌ Failed to create project. Please check your permissions and try again."
      exit 1
    fi
    echo "✅ Project created successfully!"
    break
  else
    PROJECT_EXISTS=$(gcloud projects describe $GCP_PROJECT_ID --format="value(projectId)" 2>/dev/null)
    if [ -n "$PROJECT_EXISTS" ]; then
      echo "✅ Using existing project: $GCP_PROJECT_ID"
      break
    else
      echo "❌ Project '$GCP_PROJECT_ID' does not exist. Please enter a valid project ID."
    fi
  fi
done

# Set the project in gcloud config
gcloud config set project $GCP_PROJECT_ID

# Store the project ID in .env
sed -i "s|GCP_PROJECT_ID=.*|GCP_PROJECT_ID=$GCP_PROJECT_ID|g" .env

# 4.2 Check if Billing is Enabled
echo "🔹 Checking if billing is enabled for project $GCP_PROJECT_ID..."
BILLING_STATUS=$(gcloud beta billing projects describe $GCP_PROJECT_ID --format="value(billingEnabled)")

if [ "$BILLING_STATUS" != "True" ]; then
  echo "❌ Billing is not enabled for this project!"
  echo "To proceed, you must enable billing manually."

  # Show available billing accounts
  echo "🔹 Available billing accounts:"
  gcloud beta billing accounts list

  echo "🔹 Follow these steps to enable billing:"
  echo "   1️⃣ Go to the Billing Console: https://console.cloud.google.com/billing"
  echo "   2️⃣ Select or link a billing account to your project: $GCP_PROJECT_ID"
  echo "   3️⃣ Once billing is activated, re-run this script."

  exit 1
fi

echo "✅ Billing is already enabled."

#FIXME: NEED TO ADD A WAIT HERE TO ENSURE PERMISSIONS ARE SET BEFORE PROCEEDING

# Update Application Default Credentials quota project
echo "🔹 Granting 'serviceusage.services.use' permission to the authenticated user..."
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
    --member="user:$USER_EMAIL" \
    --role="roles/serviceusage.serviceUsageConsumer"


# Verify the permission was granted
PERMISSION_CHECK=$(gcloud projects get-iam-policy $GCP_PROJECT_ID --flatten="bindings[].members" --format="value(bindings.role)" | grep "roles/serviceusage.serviceUsageConsumer")

if [ -z "$PERMISSION_CHECK" ]; then
    echo "❌ Failed to grant 'serviceusage.services.use' permission. Exiting..."
    exit 1
fi

# Retry setting the Application Default Credentials quota project
echo "🔹 Setting Application Default Credentials quota project..."
if ! gcloud auth application-default set-quota-project $GCP_PROJECT_ID; then
    echo "⚠️ Warning: Failed to set quota project. Please ensure the authenticated user has the 'serviceusage.services.use' permission."
fi

#FIXME: NEED TO ADD A WAIT HERE TO ENSURE PERMISSIONS ARE SET BEFORE PROCEEDING
echo "⏳ Waiting for permissions to propagate..."
sleep 10  # Wait for 60 seconds to ensure permissions are set

#NOTE: Create a Dedicated Storage Admin Service Account
# 5 Create a Dedicated Storage Admin Service Account

STORAGE_ADMIN_NAME="storage-admin"
STORAGE_ADMIN_EMAIL="$STORAGE_ADMIN_NAME@$GCP_PROJECT_ID.iam.gserviceaccount.com"
KEY_FILE_PATH="secrets/gcp_credentials.json"

echo "🔹 Checking if Storage Admin Service Account exists..."
EXISTING_SA=$(gcloud iam service-accounts list --format="value(email)" --filter="email:$STORAGE_ADMIN_EMAIL")

if [ -n "$EXISTING_SA" ]; then
    echo "⚠️ Storage Admin service account already exists. Deleting it..."

    # List and delete all associated keys first
    EXISTING_KEYS=$(gcloud iam service-accounts keys list --iam-account=$STORAGE_ADMIN_EMAIL --format="value(name)")
    
    if [ -n "$EXISTING_KEYS" ]; then
    for KEY in $EXISTING_KEYS; do
        gcloud iam service-accounts keys delete $KEY --iam-account=$STORAGE_ADMIN_EMAIL --quiet || {
            echo "⚠️ Warning: Failed to delete key $KEY. It might have already been deleted or precondition check failed."
        }
        echo "✅ Deleted key: $KEY"
    done
    fi
    
    # Delete the service account
    gcloud iam service-accounts delete $STORAGE_ADMIN_EMAIL --quiet || {
        echo "⚠️ Warning: Failed to delete service account $STORAGE_ADMIN_EMAIL. It might have already been deleted or precondition check failed."
    }
    echo "✅ Deleted service account: $STORAGE_ADMIN_EMAIL"

    echo "⏳ Waiting for GCP to fully remove the service account..."
    while gcloud iam service-accounts list --format="value(email)" --filter="email:$STORAGE_ADMIN_EMAIL" | grep -q "$STORAGE_ADMIN_EMAIL"; do
        echo "🔄 Still deleting... waiting 10 seconds..."
        sleep 10
    done
    echo "✅ Service account fully removed."

    # 🛠 ADD A NEW WAIT TO AVOID IMMEDIATE RE-CREATION
    echo "⏳ Giving Google Cloud some extra time before creating a new service account..."
    sleep 30  # Wait an additional 30 seconds before proceeding

fi

# 6.1 Create a New Storage Admin Service Account
echo "🔹 Creating new Storage Admin service account: $STORAGE_ADMIN_NAME..."
gcloud iam service-accounts create $STORAGE_ADMIN_NAME --display-name "Storage Admin Service Account"

# Add a delay before checking the service account to avoid the warning
sleep 10

# Verify the account was created before proceeding
NEW_SA=$(gcloud iam service-accounts list --format="value(email)" --filter="email:$STORAGE_ADMIN_EMAIL")

if [ -z "$NEW_SA" ]; then
    echo "❌ ERROR: Storage Admin service account creation failed. Please check GCP console."
    exit 1
fi

# 6.2 Assign **ALL** IAM Roles to the Storage Admin Service Account
echo "🔹 Assigning **FULL** IAM permissions to the Storage Admin service account..."
FULL_ROLES=(
    "roles/owner"                  # Full control over the project
    "roles/editor"                 # Edit permissions for all resources
    "roles/storage.admin"          # Full control over Cloud Storage
    "roles/storage.objectAdmin"    # Full control over objects in Cloud Storage
    "roles/storage.objectCreator"  # Allows object creation (uploads)
    "roles/storage.objectViewer"   # Allows viewing objects
    "roles/storage.objectUser"     # Grants object-level permissions
    "roles/bigquery.admin"         # Full control over BigQuery
    "roles/iam.serviceAccountAdmin" # Allows full control over service accounts
    "roles/iam.roleAdmin"          # Allows managing IAM roles
    "roles/logging.admin"          # Full control over logs
    "roles/cloudsql.admin"         # Full control over Cloud SQL
    "roles/dataproc.admin"         # Full control over Dataproc
    "roles/pubsub.admin"           # Full control over Pub/Sub
    "roles/compute.admin"          # Full control over Compute Engine
)

for role in "${FULL_ROLES[@]}"; do
    gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
        --member="serviceAccount:$STORAGE_ADMIN_EMAIL" \
        --role="$role"
done

echo "✅ IAM permissions successfully assigned!"

# NOTE: Check any permissions errors 
# 6.3 Generate a New Service Account Key for the Storage Admin
echo "🔹 Generating a new service account key for Storage Admin..."

# Remove existing key file if it exists
if [ -f "$KEY_FILE_PATH" ]; then
    rm -f $KEY_FILE_PATH
fi

# Ensure the secrets directory exists and has the correct permissions
mkdir -p secrets
chmod 755 secrets  # Ensure directory is accessible

KEY_FILE_PATH="secrets/gcp_credentials.json"

gcloud iam service-accounts keys create $KEY_FILE_PATH --iam-account=$STORAGE_ADMIN_EMAIL

# Ensure the key has the correct permissions
chmod 644 $KEY_FILE_PATH  # Make it readable by all users but writable only by the owner
chown $(id -u):$(id -g) $KEY_FILE_PATH  # Ensure the correct user owns it

# Ensure the key is accessible inside the container
docker exec -it airflow-webserver chmod 644 /opt/airflow/keys/gcp_credentials.json 2>/dev/null || true
docker exec -it airflow-webserver chown airflow:airflow /opt/airflow/keys/gcp_credentials.json 2>/dev/null || true

# Store key path in .env
sed -i "s|GOOGLE_APPLICATION_CREDENTIALS=.*|GOOGLE_APPLICATION_CREDENTIALS=$KEY_FILE_PATH|g" .env

echo "✅ Storage Admin service account created, full permissions assigned, and key downloaded successfully!"

# ✅ Set Google Cloud Storage (Data Lake) AFTER GCP_PROJECT_ID is confirmed
GCS_BUCKET="$(gcloud config get-value project)-datalake"

# Check if GCS_BUCKET already exists in .env, then update or append accordingly
if grep -q "^GCS_BUCKET=" .env; then
    sed -i "s|^GCS_BUCKET=.*|GCS_BUCKET=$GCS_BUCKET|g" .env
else
    echo "GCS_BUCKET=$GCS_BUCKET" >> .env
fi

echo "✅ Using bucket: $GCS_BUCKET"

echo "LOCAL_STORAGE=/opt/airflow/processed_data/raw/csv" >> .env

#NOTE: Deploy Infrastructure

# 5️⃣ Deploy Infrastructure
echo "🔹 Initializing Terraform..."
cd terraform || { echo "❌ Terraform folder not found! Exiting..."; exit 1; }
terraform init || { echo "❌ Terraform initialization failed! Exiting..."; exit 1; }

# Check if the user has the required permissions to create storage buckets
echo "🔹 Checking permissions for creating storage buckets..."
if ! gcloud projects get-iam-policy $GCP_PROJECT_ID --flatten="bindings[].members" --format="value(bindings.role)" | grep -q "roles/storage.admin"; then
    echo "❌ ERROR: The authenticated user does not have 'roles/storage.admin' permission. Please grant the required permissions and re-run the script."
    exit 1
fi

echo "🔹 Applying Terraform configuration..."
if ! terraform apply -var="project_id=$GCP_PROJECT_ID" -var="gcs_location=us-central1" -auto-approve; then
    echo "⚠️ Warning: Terraform failed to create the bucket. Checking if the bucket already exists..."
    if gsutil ls -b "gs://${GCP_PROJECT_ID}-datalake" &>/dev/null; then
        echo "✅ Bucket already exists: gs://${GCP_PROJECT_ID}-datalake"
        DATALAKE_BUCKET_NAME="${GCP_PROJECT_ID}-datalake"
    else
        echo "❌ Terraform failed and the bucket does not exist. Exiting..."
        exit 1
    fi
else
    # Fetch Data Lake Bucket Name
    DATALAKE_BUCKET_NAME=$(terraform output -raw datalake_bucket_name)
fi

# Store bucket name in .env
sed -i "s|GCS_RAW_BUCKET_NAME=.*|GCS_RAW_BUCKET_NAME=$DATALAKE_BUCKET_NAME|g" ../.env

echo "✅ GCS Data Lake created: gs://$DATALAKE_BUCKET_NAME"
cd ..

#TODO: needs to to be changed   to docker-compose up -d but with some logs


# 6️⃣ Start Docker Containers
echo "🔹 Starting Docker services..."
docker-compose up --build -d

# 7️⃣ Wait for Airflow Webserver
echo "⏳ Waiting for Airflow to initialize..."
sleep 20  # Adjust time if needed

# 8️⃣ Verify Airflow is Running
if docker ps | grep -q "airflow_webserver"; then
    echo "✅ Airflow Webserver is running."
else
    echo "❌ Airflow Webserver failed to start. Check logs using: docker logs airflow_webserver"
    exit 1
fi

# 9️⃣ Unpause & Trigger DAG
echo "🔹 Unpausing and triggering Airflow DAG..."
docker exec -it airflow-webserver airflow dags unpause end_to_end_pipeline
docker exec -it airflow-webserver airflow dags trigger end_to_end_pipeline

NOTE: check port 8082 for Airflow and 8501 for Streamlit
# 🔟 Display URLs
AIRFLOW_DASHBOARD_URL="http://localhost:8082"
STREAMLIT_DASHBOARD_URL="http://localhost:8501"
sed -i "s|AIRFLOW_DASHBOARD_URL=.*|AIRFLOW_DASHBOARD_URL=$AIRFLOW_DASHBOARD_URL|g" .env

echo "✅ Setup Complete!"
echo "📊 Visit your Airflow Dashboard: $AIRFLOW_DASHBOARD_URL"
echo "📊 Visit your Streamlit Dashboard: $STREAMLIT_DASHBOARD_URL"