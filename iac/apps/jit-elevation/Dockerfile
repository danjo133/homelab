FROM python:3.12-slim

WORKDIR /app

COPY main.py .
COPY static/ static/

EXPOSE 8080

USER nobody
CMD ["python", "main.py"]
