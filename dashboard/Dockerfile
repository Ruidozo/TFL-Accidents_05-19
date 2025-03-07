# Use an official Python image
FROM python:3.9

# Set working directory
WORKDIR /usr/app/dashboard

# Copy and install dependencies from the current directory
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir folium streamlit_folium

# Copy dashboard app files
COPY . .

# Expose the default Streamlit port
EXPOSE 8501

# Run the Streamlit application
CMD ["python", "-m", "streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]