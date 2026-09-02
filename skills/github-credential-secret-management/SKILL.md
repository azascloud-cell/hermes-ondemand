---
name: github-credential-secret-management
description: "GitHub repository secrets via API (public-key encryption), token validation, model fallback discovery."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
tags: [GitHub, secrets, credentials, python, sodium, API-key]
related_skills: [github-auth, github-pr-workflow]
---  

# GitHub Credential & Secret Management via API

## Overview  
Set repository secrets, validate API keys, and discover valid model fallbacks **without `gh` CLI** — using only the GitHub REST API, `libsodium`/`pynacl`/`tweetnacl`, and `curl`.  

Proven approach used for setting `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, etc. against a GitHub repo using its REST API + Sodium sealed-box encryption.

---

## Detection Flow  

Before managing secrets, verify:  
1. You have a **GitHub PAT** with scope `repo` + `workflow`.  
2. The repo exists and you're listed as collaborator/owner.  
3. No `gh CLI` is required — pure HTTPS API calls suffice.  

```bash
# Check PAT validity
curl -s -H "Authorization: token ***" https://api.github.com/user | jq '{login, name}'

# Check if repo is accessible
curl -s -H "Authorization: token ***" https://api.github.com/repos/<OWNER>/<REPO> | jq '.full_name'
```

---

## Method: Set Secret via GitHub Public-Key Encryption  

> Pitfall: `gh secret set` requires `gh` + login. This method works headless.

### Requirements
- `pynacl` (Python) or `libsodium-wrappers` (Node.js)

### Steps (Python)
1. Fetch repo public key:  
   ```bash
   curl -s -H "Authorization: token ***" \
     https://api.github.com/repos/<OWNER>/<REPO>/actions/secrets/public-key
   ```

2. Encrypt the secret value with the public key using **SealedBox**:
   ```python
   import base64
   from nacl.public import PublicKey, SealedBox

   pubkey_bytes = base64.b64decode("<public-key-json-here>")
   public_key = PublicKey(pubkey_bytes)
   sealed_box = SealedBox(public_key)
   encrypted = sealed_box.encrypt(secret_value.encode())
   encrypted_value = base64.b64encode(encrypted).decode()
   ```

3. PUT the encrypted value + key ID back to GitHub:
   ```bash
   curl -s -X PUT \
     -H "Authorization: token ***" \
     -H "Accept: application/vnd.github.v3+json" \
     https://api.github.com/repos/<OWNER>/<REPO>/actions/secrets/SECRET_NAME \
     -d '{"encrypted_value": "<encrypted_b64>", "key_id": "<key_id>"}'
   ```

### Steps (Node.js)
```bash
npm install libsodium-wrappers
```

```js
const sodium = require('libsodium-wrappers');

async function setGitHubSecret({ token, repo, name, value }) {
  // 1. Get public key
  const res = await fetch(`https://api.github.com/repos/${repo}/actions/secrets/public-key`, {
    headers: { Authorization: `token ${token}`, Accept: "application/vnd.github.v3+json" }
  });
  const { key, key_id } = await res.json();

  // 2. Encrypt with libsodium SealedBox
  await sodium.ready;
  const pk = Buffer.from(key, 'base64');
  const sealedBox = sodium.crypto_box_seal(sodium.from_string(value), pk);
  const encryptedValue = Buffer.from(sealedBox).toString('base64');

  // 3. PUT to GitHub
  await fetch(`https://api.github.com/repos/${repo}/actions/secrets/${name}`, {
    method: 'PUT',
    headers: { Authorization: `token ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ encrypted_value: encryptedValue, key_id })
  });
}
```

---

## Validation: Test API Keys Before Deployment  

Use raw HTTP calls to pre-validate keys before adding to GitHub Actions.

### Gemini (Generative Language API v1beta)
```bash
# Check available models (lists only what your project is allowed to use)
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=***" | jq '.models[].name'

# Test generation
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=***" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"Reply JSON: {\"status\":\"ok\"}"}]}]}'
```

⚠️ **Common error:** `HTTP 403: Project denied access` → means the **Google Cloud project hasn’t enabled the Generative Language API**.  
🔧 Fix: Go to [Google Cloud Console](https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com) → Enable API.

---

### OpenRouter
```bash
# List free models
curl -s -H "Authorization: Bearer ***" https://openrouter.ai/api/v1/models | jq '[.data[] | select(.id | endswith(":free")) | .id]'

# Test a free model
curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Authorization: Bearer ***" \
  -H "HTTP-Referer: https://your-app.com" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "poolside/laguna-s-2.1:free",
    "messages": [{"role":"user","content":"Reply: {\"status\":\"ok\"}"}],
    "max_tokens": 20
  }'
```

⚠️ **Rate limit:** OpenRouter free tier allows ~20 req/min. Wait 30+ seconds between tests.

---

### Groq
```bash
# Test key
curl -s -H "Authorization: Bearer ***" https://api.groq.com/openai/v1/models | jq '.data[0].id'
```

---

## Model Fallback Discovery Strategy  

When a model returns `404` or `403`, use these known-good fallbacks:

| Provider | Primary | Fallback |
|----------|---------|----------|
| Gemini   | `gemini-3.6-flash` | `gemini-3.5-flash` |
| OpenRouter | `poolside/laguna-s-2.1:free` | `deepseek/deepseek-chat:free` |
| Groq     | `llama-3.3-70b-versatile` | `gemma2-9b-it` |

Query the provider’s `/models` endpoint to get the real-time list of available models.

---

## Pitfalls & Gotchas  

| Symptom | Cause | Fix |
|--------|-------|-----|
| `gh CLI: command not found` | Not installed or not in PATH | Use REST API + Sodium encryption instead |
| `HTTP 403: Project denied access` | Google Cloud project hasn't enabled API | Enable via [Cloud Console](https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com) |
| `HTTP 429: rate limit` | Too many rapid requests to OpenRouter free tier | Wait 30s cooldown, or switch model |
| `libsodium not found` | npm package mismatch | `npm install libsodium-wrappers` — works in Node ≥ 18 |
| `pynacl missing` | `pip install pynacl` in user space | `pip install --user pynacl`  |

---

## Templates  

Refer to [`templates/set-github-secret.py`](templates/set-github-secret.py) for a drop-in script to set any secret via CLI.

---

## References  

- [GitHub Create Repository Secret API](https://docs.github.com/en/rest/actions/secrets#create-repository-secret)
- [libsodium sealed box encryption](https://doc.libsodium.org/public-key_cryptography/sealed_boxes)
- [Google Generative Language API v1beta](https://ai.google.dev/api/generate-content)
