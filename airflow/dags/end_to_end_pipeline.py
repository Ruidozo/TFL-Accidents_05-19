from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import subprocess
import logging
import os

# Configure logging
logging.basicConfig(
    format='%(asctime)s [%(levelname)s]: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    level=logging.INFO
)

# Default arguments
default_args = {
    'owner': 'airflow',
    'start_date': datetime(2024, 2, 27),
    'catchup': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Initialize DAG
with DAG(
    'end_to_end_pipeline',
    default_args=default_args,
    description='ETL + dbt in a single end-to-end pipeline',
    schedule_interval=None,
    max_active_runs=1,
) as dag:

    # Function to run Python scripts
    def run_script(script_name):
        logging.info(f"🚀 Running script: {script_name}...")
        GCS_BUCKET = os.getenv('GCS_BUCKET').strip()
        logging.info(f"Using bucket name: '{GCS_BUCKET}' (length: {len(GCS_BUCKET)})")
        
        process = subprocess.Popen(
            ["python", f"/usr/app/dlt/{script_name}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Capture stdout
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                logging.info(f"{script_name} [STDOUT]: {output.strip()}")

        # Capture stderr
        stderr_output = process.stderr.read().strip()
        if stderr_output:
            logging.error(f"{script_name} [STDERR]: {stderr_output}")

        exit_code = process.poll()
        if exit_code != 0:
            raise Exception(f"❌ Script {script_name} failed with exit code {exit_code}")
        else:
            logging.info(f"✅ Script {script_name} executed successfully.")

    # ETL Tasks
    accident_data_task = PythonOperator(
        task_id='accident_data_pipeline',
        python_callable=lambda: run_script('accident_data_pipeline.py'),
    )

    weather_task = PythonOperator(
        task_id='weather_loader',
        python_callable=lambda: run_script('weather_loader.py'),
    )

    # dbt Transformation
    dbt_run = BashOperator(
        task_id='dbt_run',
        bash_command='cd /usr/app/dbt && dbt run --profiles-dir .',
    )

    # Task dependencies
    [accident_data_task, weather_task] >> dbt_run
