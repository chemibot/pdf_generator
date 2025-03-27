from flask import Flask, request, redirect, render_template, url_for
from datetime import datetime
import boto3
import os
from fpdf import FPDF

app = Flask(__name__)

S3_BUCKET = os.environ.get("S3_BUCKET")
S3_REGION = os.environ.get("AWS_REGION", "eu-west-1")
CLOUDFRONT_DOMAIN = os.environ.get("CLOUDFRONT_DOMAIN")

s3 = boto3.client("s3", region_name=S3_REGION)

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/pdf")
def generate_pdf():
    name = request.args.get("name", "Desconocido")
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"{name}_{timestamp}.pdf"
    filepath = f"/tmp/{filename}"

    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Arial", size=16)
    pdf.cell(200, 10, txt=f"Hola, {name}", ln=True, align='C')
    pdf.output(filepath)

    s3.upload_file(filepath, S3_BUCKET, f"pdfs/{filename}", ExtraArgs={"ContentType": "application/pdf"})

    return redirect(f"http://{CLOUDFRONT_DOMAIN}/pdfs/{filename}")

@app.route("/historial")
def historial():
    if not S3_BUCKET or not CLOUDFRONT_DOMAIN:
        return f"Error: S3_BUCKET={S3_BUCKET}, CLOUDFRONT_DOMAIN={CLOUDFRONT_DOMAIN}", 500

    try:
        response = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix="pdfs/")
        archivos = []

        if "Contents" in response:
            for obj in response["Contents"]:
                archivos.append({
                    "nombre": obj["Key"].replace("pdfs/", ""),
                    "url": f"http://{CLOUDFRONT_DOMAIN}/{obj['Key']}"
                })

        return render_template("historial.html", archivos=archivos)
    except Exception as e:
        return f"Error accediendo a S3: {str(e)}", 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
