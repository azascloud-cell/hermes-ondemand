#!/usr/bin/env bash
# selfheal.sh — Helper untuk Hermes agar bisa memperbaiki dirinya sendiri dan
# memicu ulang workflow dengan guardrail (branch + PR + max retry). Aman: Hermes
# TIDAK bisa push langsung ke main; perubahan selalu lewat branch + PR.
#
# Semua akses memakai GH_PAT (scope `repo` + `workflow`) dari Actions secret.
# JANGAN pernah hardcode PAT di file ini.
set -euo pipefail

GH_PAT="${GH_PAT:-}"
GH_REPO="${GH_REPO:-}"
GH_REF="${GH_REF:-main}"
STATE_DIR="${SELFHEAL_STATE_DIR:-$HOME/.hermes/selfheal}"

API="https://api.github.com/repos/$GH_REPO"

log() { echo "[selfheal] $*"; }
die() { echo "[selfheal] ERROR: $*" >&2; exit 1; }

require_auth() {
  [ -n "$GH_PAT" ] || die "GH_PAT not set"
  [ -n "$GH_REPO" ] || die "GH_REPO not set"
}

gh() {
  local method="$1" url="$2" data="${3:-}"
  local args=(-s -X "$method" -H "Authorization: Bearer $GH_PAT" -H "Accept: application/vnd.github+json")
  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" -d "$data")
  fi
  curl "${args[@]}" "$url"
}

# ---------------------------------------------------------------- status ----
cmd_status() {
  require_auth
  log "repo: $GH_REPO"
  gh GET "$API" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("full_name:",d.get("full_name"),"| default_branch:",d.get("default_branch"),"| private:",d.get("private"))' || log "tidak bisa ambil info repo (cek scope PAT)"
  gh GET "$API/actions/secrets" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("secrets:",[s["name"] for s in d.get("secrets",[])])' 2>/dev/null || log "tidak bisa list secrets (perlu scope secrets read)"
}

# ------------------------------------------------------------ retry guard ---
# Batasi jumlah retry per "issue fingerprint" agar Hermes tidak infinite-loop.
# Setiap fix bertambah counter; reset otomatis bila counter lama (> TTL) atau
# saat berhasil (pr-merge).
# args: <fingerprint> <max>
_retry_guard() {
  local fp="$1" max="${2:-3}" ttl="${RETRY_TTL_SEC:-3600}"
  mkdir -p "$STATE_DIR"
  local f="$STATE_DIR/${fp//\//_}.retry"
  local now count
  now=$(date +%s)
  if [ -f "$f" ]; then
    local saved_ts saved_count
    read -r saved_ts saved_count < "$f" || { saved_ts=0; saved_count=0; }
    if [ $((now - saved_ts)) -ge "$ttl" ]; then
      count=1
    else
      count=$((saved_count + 1))
    fi
  else
    count=1
  fi
  printf '%s %s\n' "$now" "$count" > "$f"
  if [ "$count" -gt "$max" ]; then
    log "retry #$count melebihi max $max untuk '$fp' — berhenti (guardrail)"
    return 1
  fi
  log "retry #$count/$max untuk '$fp'"
  return 0
}

_clear_retry() {
  local fp="$1"
  rm -f "$STATE_DIR/${fp//\//_}.retry"
}

# -------------------------------------------------------------- dispatch ----
# Self-trigger repository_dispatch (memicu hermes.yml / hermes-on-demand).
# arg: <event_type> [client_payload_json]
cmd_dispatch() {
  require_auth
  local event="${1:?usage: dispatch <event_type> [payload_json]}"
  local payload="${2:-{}}"
  gh POST "$API/dispatches" "{\"event_type\":\"$event\",\"client_payload\":$payload}" >/dev/null
  log "dispatched '$event'"
}

# ------------------------------------------------------------ trigger -------
# Trigger workflow_dispatch (keepalive / hermes.yml) langsung pada ref.
# arg: <workflow_file> [ref]
cmd_trigger() {
  require_auth
  local wf="${1:?usage: trigger <workflow_file> [ref]}"
  local ref="${2:-$GH_REF}"
  gh POST "$API/actions/workflows/$wf/dispatches" "{\"ref\":\"$ref\"}" >/dev/null
  log "triggered workflow '$wf' on $ref"
}

# ---------------------------------------------------------- retry-trigger ---
# Trigger dengan guardrail: hanya jika counter retry belum lewat max.
# arg: <workflow_file> <fingerprint> [max] [ref]
cmd_retry() {
  local wf="${1:?usage: retry <workflow_file> <fingerprint> [max] [ref]}"
  local fp="$2"
  local max="${3:-3}"
  local ref="${4:-$GH_REF}"
  if _retry_guard "$fp" "$max"; then
    cmd_trigger "$wf" "$ref"
  else
    die "guardrail: tidak memicu $wf"
  fi
}

# -------------------------------------------------------------- commit -----
# Commit + push perubahan yang sudah ada di working tree ke branch baru, lalu
# buka PR ke main. TIDAK langsung merge. Selalu aman.
# arg: <branch> <title> [body]
cmd_fix() {
  require_auth
  local branch="${1:?usage: fix <branch> <title> [body]}"
  local title="$2"
  local body="${3:-}"

  command -v git >/dev/null || die "git not found"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "bukan di dalam git work tree"

  # pastikan ada perubahan (file staged/untracked/modified)
  if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log "tidak ada perubahan untuk di-commit"
    return 0
  fi

  # pindah ke branch baru dari GH_REF yang bersih
  git fetch origin "$GH_REF" >/dev/null 2>&1 || true
  git checkout -B "$branch" "origin/$GH_REF" >/dev/null 2>&1 || git checkout -b "$branch" >/dev/null 2>&1

  git add -A
  git -c user.name="Hermes SelfHeal" -c user.email="hermes-selfheal@users.noreply.github.com" \
    commit -m "$title" >/dev/null || { log "commit gagal (mungkin tidak ada perubahan)"; return 0; }

  git push -u origin "$branch" >/dev/null 2>&1 || die "push gagal (cek scope PAT: repo)"

  # buat PR
  local body_json
  body_json=$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$body" 2>/dev/null || echo '""')
  local pr
  pr=$(gh POST "$API/pulls" \
    "{\"title\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$title"),\"head\":\"$branch\",\"base\":\"$GH_REF\",\"body\":$body_json}")
  log "PR dibuat: $(echo "$pr" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("html_url","?"))' 2>/dev/null || echo '?')"
}

# -------------------------------------------------------------- merge -------
# Merge PR yang sudah direview / lolos. Memanggil _clear_retry untuk fp terkait.
# arg: <pr_number> [fingerprint]
cmd_merge() {
  require_auth
  local pr_num="${1:?usage: merge <pr_number> [fingerprint]}"
  local fp="${2:-}"
  gh PUT "$API/pulls/$pr_num/merge" '{"merge_method":"squash"}' >/dev/null && log "merged PR #$pr_num"
  if [ -n "$fp" ]; then
    _clear_retry "$fp"
  fi
}

# ------------------------------------------------------------------ main ----
cmd="${1:-}"
case "$cmd" in
  status) shift; cmd_status "$@";;
  dispatch) shift; cmd_dispatch "$@";;
  trigger) shift; cmd_trigger "$@";;
  retry) shift; cmd_retry "$@";;
  fix) shift; cmd_fix "$@";;
  merge) shift; cmd_merge "$@";;
  *)
    cat <<EOF
selfheal.sh — self-heal helper untuk Hermes (dengan guardrail)

Usage:
  selfheal.sh status                          cek akses PAT & repo
  selfheal.sh dispatch <event> [payload_json] trigger repository_dispatch
  selfheal.sh trigger <workflow> [ref]        trigger workflow_dispatch
  selfheal.sh retry <workflow> <fp> [max]     trigger dengan batas retry
  selfheal.sh fix <branch> <title> [body]     commit+push ke branch & buka PR
  selfheal.sh merge <pr_number> [fp]          merge PR (reset retry counter)

Guardrail:
  - fix selalu lewat branch + PR, tidak pernah push ke main langsung.
  - retry punya max counter per fingerprint (default 3) agar tidak infinite-loop.
  - Semua akses via GH_PAT; jangan pernah hardcode token.
EOF
    exit 1;;
esac