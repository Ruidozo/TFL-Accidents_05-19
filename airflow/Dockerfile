FROM apache/airflow:2.7.2-python3.9

ENV AIRFLOW_HOME=/opt/airflow

# Install dependencies as root
USER root
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    python3-dev \
    python3-pip \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create airflow user and group if they do not exist
RUN groupadd -r airflow || true && useradd -r -g airflow airflow || true

# Ensure required directories exist and have correct permissions
RUN mkdir -p /usr/app/dlt/processed_data/raw/jsonl && \
    chown -R airflow:airflow /usr/app/dlt/processed_data && \
    chmod -R 775 /usr/app/dlt/processed_data

RUN mkdir -p /opt/airflow/keys && \
    chown -R airflow:airflow /opt/airflow/keys && \
    chmod -R 755 /opt/airflow/keys

# Ensure the logs directory for dbt has the correct permissions
RUN mkdir -p /usr/app/dbt/logs && \
    chown -R airflow:airflow /usr/app/dbt/logs && \
    chmod -R 775 /usr/app/dbt/logs

# Switch to airflow user to install Python packages
USER airflow
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# Switch to airflow user and install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
ENV PATH="/home/airflow/.cargo/bin:${PATH}"

# Switch back to root to copy entrypoint script and set permissions
USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Switch back to airflow user
USER airflow
ENTRYPOINT ["/entrypoint.sh"]