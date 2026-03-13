# ─── RESOURCE GROUP ─────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = var.project_name
  location = var.location
}

# ─── STORAGE ACCOUNT (Blob Storage) ─────────────────────────────────────────
resource "azurerm_storage_account" "main" {
  name                     = "devopsromainstore"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "main" {
  name                  = "fichiers"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ─── POSTGRESQL ──────────────────────────────────────────────────────────────
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "devops-romain-db"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = "14"
  administrator_login    = "admindb"
  administrator_password = var.admin_password
  sku_name               = "B_Standard_B1ms"
  storage_mb             = 32768
  zone                   = "2"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "main" {
  name             = "allow-all"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# ─── RÉSEAU ──────────────────────────────────────────────────────────────────
resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "${var.project_name}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                = "${var.project_name}-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "main" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-flask"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "main" {
  name                = "${var.project_name}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# ─── MACHINE VIRTUELLE ───────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "main" {
  name                = "${var.project_name}-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.main.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOT
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y python3 python3-pip libpq-dev

    mkdir -p /opt/flaskapp
    cd /opt/flaskapp

    cat > requirements.txt << 'REQEOF'
flask==3.0.0
azure-storage-blob==12.19.0
psycopg2-binary==2.9.9
REQEOF

    cat > app.py << 'PYEOF'
from flask import Flask, request, jsonify
from azure.storage.blob import BlobServiceClient
import psycopg2, uuid, datetime, os

app = Flask(__name__)

STORAGE_CONN_STR = "${azurerm_storage_account.main.primary_connection_string}"
CONTAINER_NAME   = "fichiers"
DB_HOST          = "${azurerm_postgresql_flexible_server.main.fqdn}"
DB_NAME          = "postgres"
DB_USER          = "admindb"
DB_PASS          = "${var.admin_password}"

def get_db():
    return psycopg2.connect(
        host=DB_HOST, database=DB_NAME,
        user=DB_USER, password=DB_PASS, sslmode="require"
    )

def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS fichiers (
            id TEXT PRIMARY KEY,
            filename TEXT,
            blob_path TEXT,
            uploaded_at TEXT
        )
    """)
    conn.commit()
    cur.close()
    conn.close()

@app.route("/", methods=["GET"])
def index():
    return jsonify({"status": "ok", "message": "Flask API fonctionne !"}), 200

@app.route("/upload", methods=["POST"])
def upload_file():
    if "file" not in request.files:
        return jsonify({"error": "Aucun fichier fourni"}), 400
    f = request.files["file"]
    file_id = str(uuid.uuid4())
    blob_path = f"{file_id}_{f.filename}"
    client = BlobServiceClient.from_connection_string(STORAGE_CONN_STR)
    blob_client = client.get_blob_client(container=CONTAINER_NAME, blob=blob_path)
    blob_client.upload_blob(f)
    uploaded_at = datetime.datetime.utcnow().isoformat()
    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO fichiers VALUES (%s, %s, %s, %s)",
                (file_id, f.filename, blob_path, uploaded_at))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"message": "Fichier uploade", "id": file_id}), 201

@app.route("/fichiers", methods=["GET"])
def list_files():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT id, filename, blob_path, uploaded_at FROM fichiers")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([{"id": r[0], "filename": r[1], "blob_path": r[2], "uploaded_at": r[3]} for r in rows]), 200

@app.route("/fichiers/<file_id>", methods=["GET"])
def get_file(file_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT id, filename, blob_path, uploaded_at FROM fichiers WHERE id=%s", (file_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row:
        return jsonify({"error": "Fichier introuvable"}), 404
    return jsonify({"id": row[0], "filename": row[1], "blob_path": row[2], "uploaded_at": row[3]}), 200

@app.route("/fichiers/<file_id>", methods=["DELETE"])
def delete_file(file_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT blob_path FROM fichiers WHERE id=%s", (file_id,))
    row = cur.fetchone()
    if not row:
        cur.close()
        conn.close()
        return jsonify({"error": "Fichier introuvable"}), 404
    client = BlobServiceClient.from_connection_string(STORAGE_CONN_STR)
    blob_client = client.get_blob_client(container=CONTAINER_NAME, blob=row[0])
    blob_client.delete_blob()
    cur.execute("DELETE FROM fichiers WHERE id=%s", (file_id,))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"message": "Fichier supprime"}), 200

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
PYEOF

    pip3 install -r requirements.txt

    cat > /etc/systemd/system/flask.service << 'SERVICEEOF'
[Unit]
Description=Flask Application
After=network.target

[Service]
User=root
WorkingDirectory=/opt/flaskapp
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    systemctl enable flask
    systemctl start flask
  EOT
  )

  depends_on = [
    azurerm_postgresql_flexible_server.main,
    azurerm_storage_container.main
  ]
}
