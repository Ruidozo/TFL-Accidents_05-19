# Project Name: Transport Accident Analysis & Correlation with Weather in London

## Description
This project aims to analyze **road traffic accidents in London** using the **TfL AccidentStats API** and correlate them with external factors such as **weather conditions, time of day, and location-based risk factors**. By leveraging **data engineering best practices**, this project will ingest, transform, and visualize accident data to identify key insights into **accident severity, high-risk areas, and trends over time**.

## Features
- **Identify accident hotspots** in London using **geographical data**.
- Analyze the impact of **weather conditions** (rain, fog, wind) on accident occurrence.
- Compare accident risks across different **transportation modes** (cars, bikes, pedestrians, public transport).
- Identify **peak accident hours and high-risk times**.
- Generate **interactive dashboards** to explore accident trends over time.

## Tech Stack
The project utilizes the following technologies:
- **Cloud Provider:** Google Cloud Platform (GCP)
- **Infrastructure as Code:** Terraform (for provisioning GCP resources)
- **Workflow Orchestration:** Apache Airflow (for scheduling data pipeline jobs)
- **Data Ingestion:** DLT (to extract accident and weather data & store in a GCS bucket)
- **Data Processing:** PostgreSQL (CloudSQL) & dbt (for transformation and analytics)
- **Dashboard & Visualization:** Streamlit (deployed on Cloud Run)
- **Containerization:** Docker (to package and deploy the solution efficiently)

## Architecture Overview
The data pipeline follows this flow:

1. **Data Sources:**
   - **TfL AccidentStats API** (2005-2019) → Accident records, severity, locations.
   - **OpenWeather API** → Historical weather data (rain, fog, wind).
   - **Kaggle Historical London Weather Data** → Supplementary weather data.
2. **Data Ingestion:**
   - **Accident Data Pipeline (DLT)** extracts data from TfL API and loads it into **GCS Bucket (Data Lake)**.
   - **Weather Loader** extracts weather data and stores it in GCS.
3. **Data Storage:**
   - GCS Bucket stores raw accident and weather data.
   - PostgreSQL (CloudSQL) stores structured accident and weather data for analysis.
4. **Data Transformation:**
   - dbt processes the data in PostgreSQL and creates analytical models.
5. **Visualization:**
   - Streamlit application provides an interactive dashboard to explore accident trends.

![Project Architecture](ProjectdIagram.jpg)

## Installation
### Prerequisites
Ensure you have the following installed:
- Docker & Docker Compose
- Google Cloud SDK (if using GCP)
- Python 3.x

### Setup
1. Clone the repository:
   ```sh
   git clone https://github.com/Ruidozo/TFL-Accidents_05-19.git
   cd TFL-Accidents_05-19
   ```
2. Set up environment variables:
   ```sh
   cp .env.template .env
   nano .env  # Edit with your credentials
   ```
   - The setup script will automatically generate a `.env` file, but a `.env.template` is also provided for flexibility.

3. Run the project:
   ```sh
   docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock
   ```

4. Initialize the pipeline (Airflow database is initiated automatically by the script):
   ```sh
   airflow webserver & airflow scheduler
   ```

5. Access the dashboard at **[Streamlit URL]**.

## Usage
- View accident hotspots using **interactive maps**.
- Analyze the **impact of weather conditions** on accident severity.
- Explore accident **patterns based on time, location, and transport type**.

## Contributing
If you'd like to contribute, please follow these steps:
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature-branch-name`).
3. Commit your changes (`git commit -m 'Add new feature'`).
4. Push to the branch (`git push origin feature-branch-name`).
5. Create a Pull Request.

## License
This project is licensed under [MIT License].

