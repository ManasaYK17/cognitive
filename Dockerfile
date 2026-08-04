FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# build-essential + cmake: compile dlib (via face-recognition) from source, no prebuilt wheel on PyPI for Linux.
# libopenblas/liblapack: speeds up dlib's linear algebra and avoids it vendoring its own BLAS.
# libglib/libsm/libxext/libxrender: opencv-python-headless still dlopens these at import time.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libopenblas-dev \
    liblapack-dev \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
# dlib's setup.py spawns one compiler job per core; on low-RAM hosts that OOMs the build, so cap it to 1.
RUN CMAKE_BUILD_PARALLEL_LEVEL=1 pip install --no-cache-dir -r requirements.txt

COPY . .

RUN python manage.py collectstatic --noinput

EXPOSE 8000

# On Postgres, settings.py leaves the built-in apps' migrations enabled (see MIGRATION_MODULES),
# so a plain migrate handles everything in correct dependency order — no --run-syncdb needed here.
CMD sh -c "python manage.py migrate --noinput && gunicorn cognitive_assist.wsgi:application --bind 0.0.0.0:${PORT:-8000} --workers 2 --timeout 120"
