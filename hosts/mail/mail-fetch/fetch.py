#!/usr/bin/env python3
import imaplib
import json
import os
import sys
import urllib.parse
import urllib.request
import subprocess

def get_access_token(creds_file):
    with open(creds_file) as f:
        creds = json.load(f)
    
    params = {
        "client_id":     creds["client_id"],
        "client_secret": creds["client_secret"],
        "refresh_token": creds["refresh_token"],
        "grant_type":    "refresh_token",
    }

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode(params).encode()
    )

    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
        
    # Logic to update refresh token if Google rotated it
    if "refresh_token" in data and data["refresh_token"] != creds["refresh_token"]:
        creds["refresh_token"] = data["refresh_token"]
        with open(creds_file, 'w') as f:
            json.dump(creds, f, indent=4)

    return data["access_token"]

def xoauth2_string(user, token):
    s = f"user={user}\x01auth=Bearer {token}\x01\x01"
    return s.encode()

def fetch(creds_file, search_filter="UNSEEN"):
    # Read paths from Nix environment variables
    lda_path = os.environ.get("DOVECOT_LDA")
    conf_path = os.environ.get("DOVECOT_CONF")
    target_email = os.environ.get("TARGET_EMAIL")

    name = os.path.basename(creds_file).removeprefix("gmail-").removesuffix(".json")
    print(f"Fetching {name}...")

    token = get_access_token(creds_file)
    auth_string = xoauth2_string(name, token)

    imap = imaplib.IMAP4_SSL("imap.gmail.com", 993)
    imap.authenticate("XOAUTH2", lambda _: auth_string)
    imap.select("INBOX")

    _, data = imap.search(None, search_filter)
    uids = data[0].split()
    print(f"{name}: Found {len(uids)} new messages")

    for uid in uids:
        _, msg_data = imap.fetch(uid, "(RFC822)")
        raw = msg_data[0][1]
        
        # Pipe directly to LDA to trigger Sieve filters
        try:
            cmd = [lda_path, "-c", conf_path, "-e", "-d", target_email]
            subprocess.run(cmd, input=raw, check=True, capture_output=True)
            print(f"  UID {uid.decode()} delivered and filtered.")
        except subprocess.CalledProcessError as e:
            print(f"  Error delivering UID {uid.decode()}: {e.stderr.decode()}", file=sys.stderr)

    imap.logout()

if __name__ == "__main__":
    secrets_dir = sys.argv[1]
    # Maildir path argument is no longer needed as LDA handles storage

    for creds_file in sorted(f"{secrets_dir}/{f}" for f in os.listdir(secrets_dir) if f.startswith("gmail-") and f.endswith(".json")):
        try:
            fetch(creds_file)
        except Exception as e:
            print(f"Error fetching {creds_file}: {e}", file=sys.stderr)