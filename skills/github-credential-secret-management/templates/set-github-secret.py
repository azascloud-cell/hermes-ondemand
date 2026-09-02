#!/usr/bin/env python3
"""
Set a GitHub repository secret via REST API + Sodium encryption.
Usage: python set-github-secret.py <repo> <secret_name> <secret_value> [token]
Example: python set-github-secret.py azascloud-cell/Azza-Vision-AI GEMINI_API_KEY "your-key-here"
"""

import sys
import base64
import json
import urllib.request
import os

try:
    from nacl.public import PublicKey, SealedBox
except ImportError:
    print("❌ Install pynacl first: pip install pynacl")
    sys.exit(1)

def github_api(path, token, method="GET", data=None):
    url = f"https://api.github.com/repos/{path}"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "azzavision-secret-setter"
    }
    if data:
        payload = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    else:
        payload = None
        
    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.read().decode()[:200]}"}

def set_secret(repo, secret_name, secret_value, token):
    """Set a GitHub secret using Sodium sealed box encryption."""
    # 1. Get public key
    print(f"🔑 Fetching public key for {repo}...")
    pk = github_api(f"{repo}/actions/secrets/public-key", token)
    if "error" in pk:
        print(f"❌ Failed to get public key: {pk['error']}")
        return False
    
    key_id = pk['key_id']
    public_key_bytes = base64.b64decode(pk['key'])
    public_key = PublicKey(public_key_bytes)
    sealed_box = SealedBox(public_key)
    
    # 2. Encrypt secret value
    print(f"🔒 Encrypting {secret_name}...")
    encrypted = sealed_box.encrypt(secret_value.encode())
    encrypted_value = base64.b64encode(encrypted).decode()
    
    # 3. PUT to GitHub
    print(f"📤 Setting {secret_name}...")
    result = github_api(
        f"{repo}/actions/secrets/{secret_name}",
        token,
        method="PUT",
        data={"encrypted_value": encrypted_value, "key_id": key_id}
    )
    
    if "error" in result:
        print(f"❌ Failed to set secret: {result['error']}")
        return False
    else:
        print(f"✅ {secret_name} set successfully in {repo}")
        return True

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python set-github-secret.py <repo> <secret_name> <secret_value> [token]")
        sys.exit(2)
    
    repo = sys.argv[1]
    secret_name = sys.argv[2]
    secret_value = sys.argv[3]
    token = sys.argv[4] if len(sys.argv) > 4 else os.environ.get("GH_TOKEN")
    
    if not token:
        print("❌ No token provided. Set GH_TOKEN env var or pass as 4th arg.")
        sys.exit(1)
    
    set_secret(repo, secret_name, secret_value, token)
