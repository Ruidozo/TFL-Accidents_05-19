#!/bin/bash
echo "🚀 Initializing Airflow..."

# Wait for PostgreSQL to be ready
until pg_isready -h $AIRFLOW_DB_HOST -p 5432 -U $AIRFLOW_DB_USER; do
  sleep 5
done

echo "✅ PostgreSQL is ready."

# Initialize Airflow database
airflow db init

# Check if the admin user already exists
if airflow users list | grep -q "admin"; then
  echo "✅ Admin user already exists."
else
  # Create an admin user
  airflow users create \
      --username admin \
      --password zoomcamp \
      --firstname Airflow \
      --lastname Admin \
      --role Admin \
      --email admin@example.com
fi

# Start the correct Airflow service
if [[ "$1" == "webserver" ]]; then
    echo "🌐 Starting Airflow Webserver..."
    exec airflow webserver
elif [[ "$1" == "scheduler" ]]; then
    echo "📅 Starting Airflow Scheduler..."
    exec airflow scheduler
else
    exec "$@"
fi
