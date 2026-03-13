from flask import Flask, request, jsonify
from google.cloud import storage, firestore
import uuid, datetime

app = Flask(__name__)

BUCKET_NAME = "devops-romain-bucket-2024"
PROJECT_ID  = "devops-romainp12"

storage_client   = storage.Client()
firestore_client = firestore.Client(project=PROJECT_ID)

@app.route("/", methods=["GET"])
def index():
    return jsonify({"status": "ok", "message": "Flask API fonctionne !"}), 200

@app.route("/upload", methods=["POST"])
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "Aucun fichier fourni"}), 400
    f = request.files["file"]
    file_id = str(uuid.uuid4())
    filename = f"{file_id}_{f.filename}"
    bucket = storage_client.bucket(BUCKET_NAME)
    blob = bucket.blob(filename)
    blob.upload_from_file(f)
    doc_ref = firestore_client.collection("fichiers").document(file_id)
    doc_ref.set({
        "id": file_id,
        "filename": f.filename,
        "gcs_path": filename,
        "uploaded_at": datetime.datetime.utcnow().isoformat()
    })
    return jsonify({"message": "Fichier uploade", "id": file_id, "gcs_path": filename}), 201

@app.route("/fichiers", methods=["GET"])
def list_files():
    docs = firestore_client.collection("fichiers").stream()
    fichiers = [doc.to_dict() for doc in docs]
    return jsonify(fichiers), 200

@app.route("/fichiers/<file_id>", methods=["GET"])
def get_file(file_id):
    doc = firestore_client.collection("fichiers").document(file_id).get()
    if not doc.exists:
        return jsonify({"error": "Fichier introuvable"}), 404
    return jsonify(doc.to_dict()), 200

@app.route("/fichiers/<file_id>", methods=["DELETE"])
def delete_file(file_id):
    doc_ref = firestore_client.collection("fichiers").document(file_id)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"error": "Fichier introuvable"}), 404
    data = doc.to_dict()
    bucket = storage_client.bucket(BUCKET_NAME)
    blob = bucket.blob(data["gcs_path"])
    blob.delete()
    doc_ref.delete()
    return jsonify({"message": "Fichier supprime"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
