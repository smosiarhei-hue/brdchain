FROM python:3.12-slim

WORKDIR /app
COPY brdchain.py /app/brdchain.py

ENV PYTHONUNBUFFERED=1 \
    LISTEN_HOST=0.0.0.0 \
    LISTEN_PORT=1080 \
    TARGET_HOST=brd.superproxy.io \
    TARGET_PORT=44445

EXPOSE 1080
USER 65534:65534

CMD ["python", "/app/brdchain.py", "-v"]