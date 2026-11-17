#!/bin/bash
# Xinproof runner for Google Cloud. Run it in Cloud Shell:
#   bash gcp/setup.sh            (from the setup repo), or
#   curl -fsSL https://xinproof-cloud.xinproof.workers.dev/agent/gcp.sh | bash
# It shows a short code; approve it on your Runners page in Xinproof Cloud.
# Then it creates, in the current project: a service account that can only
# read your backup bucket, one e2-micro VM (free tier in us-central1, us-east1,
# us-west1) using it, and the runner on it. No inbound ports are opened.
set -euo pipefail
URL="${XINPROOF_URL:-https://xinproof-cloud.xinproof.workers.dev}"
ZONE="${1:-us-central1-a}"
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1"; }
PROJECT="$(gcloud config get-value project 2>/dev/null)"
[ -n "$PROJECT" ] || { echo "pick a project first: gcloud config set project <id>" >&2; exit 1; }

# Keep going even if this tab is closed or left (e.g. to approve the code):
# run the setup detached and follow its log here.
if [ -z "${XP_DETACHED:-}" ]; then
  SELF="$HOME/.xinproof-gcp-setup.sh"; LOGF="$HOME/xinproof-setup.log"
  curl -fsSL "$URL/agent/gcp.sh" -o "$SELF"
  : > "$LOGF" # exists before we follow it
  XP_DETACHED=1 setsid nohup bash "$SELF" "$@" >> "$LOGF" 2>&1 < /dev/null &
  PID=$!
  tail -n +1 -F "$LOGF" --pid="$PID" 2>/dev/null || { sleep 1; cat "$LOGF"; echo "Setup continues in the background; follow it with: tail -f $LOGF"; }
  exit 0
fi
say "Project: $PROJECT"

# If any step fails, say where, and send the error to the Runners page too.
LOG="$(mktemp)"; exec 2> >(tee -a "$LOG" >&2)
STEP="connecting to Xinproof Cloud"; ID=""; SECRET=""
report() {
  local code=$?
  [ "$code" -eq 0 ] && return
  printf '\n\033[1;31mSetup stopped while %s.\033[0m\n' "$STEP" >&2
  [ -n "$ID" ] || return
  local msg; msg="$(tail -c 700 "$LOG" | sed 's/\x1b\[[0-9;]*m//g' | tr '\n' ' ')"
  python3 -c 'import json,sys; print(json.dumps({"step": sys.argv[1], "message": sys.argv[2]}))' "$STEP" "$msg" |
    curl -fsS -X POST -H "X-Pair-Secret: $SECRET" -H 'Content-Type: application/json' --data-binary @- "$URL/api/v1/agent/pair/$ID/error" >/dev/null 2>&1 &&
    echo "The error is also shown on your Runners page." >&2 || true
}
trap report EXIT

say "Connecting to Xinproof Cloud"
P="$(curl -fsS -X POST "$URL/api/v1/agent/pair")"
ID="$(printf '%s' "$P" | field id)"; SECRET="$(printf '%s' "$P" | field secret)"
CODE="$(printf '%s' "$P" | field code)"; LINK="$(printf '%s' "$P" | field approve_url)"
printf '\n    Your code:  \033[1;32m%s\033[0m\n\n    Approve it on your Runners page, or open (in a new tab):\n    %s\n\n    Setup keeps going even if you close this tab. Log: ~/xinproof-setup.log\n\n' "$CODE" "$LINK"
STEP="waiting for approval"
printf 'Waiting for approval'
SETUP=""; LOC=""
for _ in $(seq 1 300); do
  R="$(curl -sS -H "X-Pair-Secret: $SECRET" "$URL/api/v1/agent/pair/$ID" || true)"
  case "$(printf '%s' "$R" | field status)" in
    approved) SETUP="$(printf '%s' "$R" | field setup_code)"; LOC="$(printf '%s' "$R" | field location)"; break ;;
    pending) printf '.'; sleep 3 ;;
    *) echo; echo "the code expired or was not approved; run this again for a new one" >&2; exit 1 ;;
  esac
done
[ -n "$SETUP" ] || { echo; echo "timed out waiting for approval" >&2; exit 1; }
echo " approved: $LOC"
BUCKET="${LOC#gs://}"; BUCKET="${BUCKET%%/*}"
SA="xinproof-runner@$PROJECT.iam.gserviceaccount.com"

STEP="turning on Compute Engine"
say "1/4 Turning on Compute Engine in $PROJECT (if it isn't already)"
gcloud services enable compute.googleapis.com --project "$PROJECT"

STEP="creating the read-only identity"
say "2/4 Read-only identity for gs://$BUCKET"
gcloud iam service-accounts describe "$SA" --project "$PROJECT" >/dev/null 2>&1 || \
  gcloud iam service-accounts create xinproof-runner --project "$PROJECT" --display-name "Xinproof runner (read-only backups)"
for _ in 1 2 3 4 5; do
  gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member "serviceAccount:$SA" --role roles/storage.objectViewer >/dev/null && break
  sleep 5 # a new service account takes a moment to be usable
done

STEP="setting up the network"
say "3/4 Network (outbound only)"
if ! gcloud compute networks describe default --project "$PROJECT" >/dev/null 2>&1; then
  gcloud compute networks describe xinproof-runner-net --project "$PROJECT" >/dev/null 2>&1 || \
    gcloud compute networks create xinproof-runner-net --project "$PROJECT" --subnet-mode auto
  NET=xinproof-runner-net
else
  NET=default
fi

STEP="creating the runner VM"
say "4/4 Runner VM (e2-micro) in $ZONE"
STARTUP=$(mktemp)
cat > "$STARTUP" <<'EOS'
#!/bin/bash
set -euo pipefail # no -x: it would print the setup code into the boot log
[ -f /etc/systemd/system/xinproof-agent.service ] && exit 0
md() { curl -fsS -H 'Metadata-Flavor: Google' "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"; }
if [ ! -f /swapfile ]; then fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile swap swap defaults 0 0' >> /etc/fstab; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get install -yq docker.io
systemctl enable --now docker
curl -fsSL "$(md xinproof-url)/agent/install.sh" | XINPROOF_SETUP_CODE="$(md xinproof-setup)" XINPROOF_LOCATIONS="$(md xinproof-locations)" sh
EOS
gcloud compute instances create xinproof-runner --project "$PROJECT" --zone "$ZONE" \
  --machine-type e2-micro --network "$NET" \
  --image-family debian-12 --image-project debian-cloud --boot-disk-size 30GB --boot-disk-type pd-standard \
  --service-account "$SA" --scopes cloud-platform --shielded-secure-boot \
  --metadata "xinproof-url=$URL,xinproof-setup=$SETUP,xinproof-locations=$LOC" \
  --metadata-from-file startup-script="$STARTUP"
rm -f "$STARTUP"
say "Done. The runner shows as Online on your Runners page in about two minutes and tests $LOC right away."
echo "To remove it later: gcloud compute instances delete xinproof-runner --zone $ZONE && gcloud iam service-accounts delete $SA"
