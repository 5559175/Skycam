# Use the image you wanted
FROM python:3.13-slim

# Install system dependencies ONCE during the build process
RUN apt-get update && apt-get install -y \
    ffmpeg \
    bc \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir flask requests

# Set the working directory
WORKDIR /app

# Run the app
CMD ["python3", "app.py"]
