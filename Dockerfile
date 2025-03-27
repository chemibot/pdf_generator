FROM python:3.9-slim

WORKDIR /app
COPY app/ /app/
RUN pip install flask boto3 fpdf

EXPOSE 5000
CMD ["python", "app.py"]