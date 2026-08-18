#!/usr/bin/env python3
"""
Gmail Warming Script - Round Robin Family Personas
Mengirim email antar akun dengan identitas keluarga (Ayah, Ibu, Kakak, Adik, Nenek, Kakek)
Jalankan via cronjob tiap 3 jam
"""

import os
import json
import random
import subprocess
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional

# ==================== KONFIGURASI ====================
BASE_DIR = Path("/home/runner/gmail_warming")
ACCOUNTS_FILE = BASE_DIR / "accounts" / "accounts.txt"
ACCOUNTS_DIR = BASE_DIR / "accounts"
LOGS_DIR = BASE_DIR / "logs"
TEMPLATES_FILE = BASE_DIR / "scripts" / "email_templates.json"
CONFIG_TEMPLATE = BASE_DIR / "accounts" / "TEMPLATE_config.toml"

# Setup logging
LOGS_DIR.mkdir(exist_ok=True)
log_file = LOGS_DIR / f"warming_{datetime.now().strftime('%Y%m%d')}.log"
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ==================== FAMILY PERSONAS ====================
FAMILY_PERSONAS = [
    "Ayah", "Ibu", "Kakak 1", "Kakak 2", "Adik", "Nenek", "Kakek"
]

# ==================== UTILITAS ====================
def load_accounts() -> List[Dict]:
    """Load accounts from accounts.txt format: email password"""
    accounts = []
    if not ACCOUNTS_FILE.exists():
        logger.error(f"Accounts file not found: {ACCOUNTS_FILE}")
        return accounts
    
    with open(ACCOUNTS_FILE, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) >= 2:
                email = parts[0]
                password = ' '.join(parts[1:])  # password bisa punya spasi
                accounts.append({
                    "email": email,
                    "password": password,
                    "email_suffix": email.split('@')[0].replace('.', '_').replace('-', '_')
                })
            else:
                logger.warning(f"Line {line_num}: Invalid format, skipping: {line}")
    return accounts

def load_templates() -> Dict:
    """Load email templates"""
    with open(TEMPLATES_FILE, 'r') as f:
        return json.load(f)

def create_himalaya_config(account: Dict) -> Path:
    """Create Himalaya config file for an account"""
    account_dir = ACCOUNTS_DIR / account["email_suffix"]
    account_dir.mkdir(exist_ok=True)
    
    config_path = account_dir / "config.toml"
    
    with open(CONFIG_TEMPLATE, 'r') as f:
        template = f.read()
    
    config_content = template.format(
        email=account["email"],
        app_password=account["password"],
        email_suffix=account["email_suffix"]
    )
    
    with open(config_path, 'w') as f:
        f.write(config_content)
    
    # Set permissions (hanya owner bisa baca)
    os.chmod(config_path, 0o600)
    
    return config_path

def run_himalaya(config_path: Path, args: List[str]) -> tuple:
    """Run himalaya command with given config"""
    cmd = ["himalaya", "-c", str(config_path)] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"
    except Exception as e:
        return -1, "", str(e)

def test_account_connection(account: Dict) -> bool:
    """Test if account can connect via IMAP"""
    config_path = create_himalaya_config(account)
    code, stdout, stderr = run_himalaya(config_path, ["list", "folders"])
    if code == 0:
        logger.info(f"✅ {account['email']}: Connected successfully")
        return True
    else:
        logger.error(f"❌ {account['email']}: Connection failed - {stderr}")
        return False

def send_email(sender_account: Dict, recipient_email: str, persona: str, templates: Dict) -> bool:
    """Send email from sender to recipient using persona"""
    config_path = create_himalaya_config(sender_account)
    
    # Get template for persona
    persona_templates = templates.get(persona, {})
    subjects = persona_templates.get("subjects", ["Kabar"])
    bodies = persona_templates.get("bodies", ["Halo"])
    signatures = persona_templates.get("signatures", [persona])
    
    # Pick random template
    subject = random.choice(subjects)
    body_template = random.choice(bodies)
    signature = random.choice(signatures)
    
    # Fill placeholders
    recipient_name = recipient_email.split('@')[0].replace('.', ' ').replace('_', ' ').title()
    sender_name = persona
    
    # Random fillers
    fillers = {
        "penerima_nama": recipient_name,
        "penerima": recipient_email,
        "lain": random.choice([a["email"].split('@')[0] for a in load_accounts() if a["email"] != sender_account["email"]]),
        "makanan": random.choice(["nasi goreng", "soto ayam", "rendang", "gado-gado", "bakso"]),
        "masalah": random.choice(["deadline deket", "rekan kerja ribet", "gaji telat", "laptop error"]),
        "pengalaman": random.choice(["salah pilih jurusan", "terlalu percaya orang", "boros belanja"]),
        "kesalahan": random.choice(["nggak tabung", "terlalu emosional", "malas belajar"]),
        "kejadian": random.choice(["meeting lucu", "rekan kerja jatuh", "makan siang bareng"]),
        "detail": random.choice(["sampe keluar air mata", "bikin perut sakit", "nggak bisa berhenti ketawa"]),
        "barang": random.choice(["headphone", "mouse", "keyboard", "monitor", "charger"]),
        "kabar": random.choice(["lulus", "naik pangkat", "pindah rumah", "nikah"]),
        "keluh": random.choice(["capek", "stress", "bosan", "sakit"]),
        "aktivitas": random.choice(["jalan pagi", "baca buku", "ngobrol sama tetangga", "taman"]),
        "nilai": random.choice(["A", "B", "C", "D", "E"]),
        "matkul": random.choice(["Matematika", "Bahasa Inggris", "Pemrograman", "Akuntansi", "Hukum"])
    }
    
    # Replace placeholders
    for key, value in fillers.items():
        body_template = body_template.replace(f"{{{key}}}", value)
        subject = subject.replace(f"{{{key}}}", value)
    
    body = f"{body_template}\n\n{signature}"
    
    # Send email
    code, stdout, stderr = run_himalaya(config_path, [
        "send",
        "--to", recipient_email,
        "--subject", subject,
        "--body", body
    ])
    
    if code == 0:
        logger.info(f"✅ {sender_account['email']} ({persona}) -> {recipient_email} | Subject: {subject}")
        return True
    else:
        logger.error(f"❌ {sender_account['email']} ({persona}) -> {recipient_email} | Error: {stderr}")
        return False

def read_inbox(account: Dict) -> bool:
    """Read inbox to simulate human activity"""
    config_path = create_himalaya_config(account)
    code, stdout, stderr = run_himalaya(config_path, ["list", "emails", "-l", "10"])
    if code == 0:
        logger.info(f"📥 {account['email']}: Inbox checked ({len(stdout.strip().split(chr(10)))} emails)")
        return True
    else:
        logger.warning(f"⚠️ {account['email']}: Inbox check failed - {stderr}")
        return False

# ==================== MAIN WARMING LOGIC ====================
def run_warming_cycle():
    """Run one warming cycle: round-robin family personas"""
    logger.info("=" * 60)
    logger.info("🔄 STARTING WARMING CYCLE")
    logger.info("=" * 60)
    
    accounts = load_accounts()
    if len(accounts) < 2:
        logger.error("Butuh minimal 2 akun untuk round-robin!")
        return
    
    templates = load_templates()
    
    # Test connections first
    logger.info("🔍 Testing account connections...")
    active_accounts = []
    for acc in accounts:
        if test_account_connection(acc):
            active_accounts.append(acc)
    
    if len(active_accounts) < 2:
        logger.error(f"Hanya {len(active_accounts)} akun aktif, butuh minimal 2")
        return
    
    logger.info(f"✅ {len(active_accounts)} akun aktif, memulai round-robin...")
    
    # Round-robin: each account sends to next account with assigned persona
    # Assign personas to accounts (cycling if more accounts than personas)
    import time
    for i, sender in enumerate(active_accounts):
        # Determine recipient (next in round-robin)
        recipient = active_accounts[(i + 1) % len(active_accounts)]
        
        # Assign persona (cycle through family)
        persona = FAMILY_PERSONAS[i % len(FAMILY_PERSONAS)]
        
        logger.info(f"📤 {sender['email']} ({persona}) -> {recipient['email']}")
        
        # Send email
        send_email(sender, recipient["email"], persona, templates)
        
        # Small delay between sends (human-like)
        time.sleep(random.uniform(5, 15))
    
    # Each account also reads inbox (simulate checking email)
    logger.info("📥 Checking inboxes...")
    for acc in active_accounts:
        read_inbox(acc)
        time.sleep(random.uniform(2, 5))
    
    logger.info("=" * 60)
    logger.info("✅ WARMING CYCLE COMPLETED")
    logger.info("=" * 60)

if __name__ == "__main__":
    run_warming_cycle()