FROM python:3.12-slim
WORKDIR /app
COPY deploy/vision_proxy_server.py /app/vision_proxy_server.py
ENV VISION_PROXY_HOST=0.0.0.0
ENV VISION_PROXY_PORT=8787
EXPOSE 8787
CMD ["python", "vision_proxy_server.py"]
