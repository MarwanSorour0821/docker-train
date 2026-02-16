# sets the base image for docker container
# minimal python 3.10 image (smaller size, fewer packages)
FROM python:3.10-slim

# sets the working directory (if not there then it creates it automatically)
WORKDIR /app

#copies files from local machine to the container
#first dot represents source (project directory on host)
#second dot represents destination (/app directory)
COPY . .

# Install dependencies (includes Django, gunicorn, redis for cache)
RUN pip install --no-cache-dir -r requirements.txt

#container will listen on this port
EXPOSE 8000

#default run command to run when server starts
CMD ["gunicorn", "lunch_rush.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "5", "--access-logfile", "-", "--capture-output", "--log-level", "info"]