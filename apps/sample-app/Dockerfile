# Minimal, real-world-shaped Dockerfile: pinned base, non-root user,
# gunicorn instead of the Flask dev server. Small enough to read in full,
# but not a toy - this is a defensible base for a real service.

FROM python:3.12-slim

ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN useradd --no-create-home --uid 1000 appuser
USER appuser

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
