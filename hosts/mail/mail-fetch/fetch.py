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
        
    if "refresh_token" in data and data["refresh_token"] != creds["refresh_token"]:
        creds["refresh_token"] = data["refresh_token"]
        with open(creds_file, 'w') as f:
            json.dump(creds, f, indent=4)

    return data["access_token"]

def xoauth2_string(user, token):
    s = f"user={user}\x01auth=Bearer {token}\x01\x01"
    return s.encode()

def fetch_account(creds_file, search_filter):
    lda_path = os.environ.get("DOVECOT_LDA")
    conf_path = os.environ.get("DOVECOT_CONF")
    target_email = os.environ.get("TARGET_EMAIL")

    name = os.path.basename(creds_file).removeprefix("gmail-").removesuffix(".json")
    print(f"--> Fetching {name} (Filter: {search_filter})...")

    try:
        token = get_access_token(creds_file)
        auth_string = xoauth2_string(name, token)

        imap = imaplib.IMAP4_SSL("imap.gmail.com", 993)
        imap.authenticate("XOAUTH2", lambda _: auth_string)
        imap.select("INBOX")

        _, data = imap.search(None, search_filter)
        uids = data[0].split()
        print(f"    Found {len(uids)} messages.")

        for uid in uids:
            _, msg_data = imap.fetch(uid, "(RFC822)")
            raw = msg_data[0][1]
            
            # -f: envelope sender (we'll use the gmail account name)
            # -a: original recipient (the headpats email)
            # -e: return error on failure
            cmd = [
                lda_path, 
                "-c", conf_path, 
                "-e", 
                "-f", name,           # Envelope sender
                "-a", target_email,   # Original recipient
                "-d", target_email    # Target mailbox
            ]

            try:
                result = subprocess.run(cmd, input=raw, check=True, capture_output=True)
                print(f"  UID {uid.decode()} delivered.")
            except subprocess.CalledProcessError as e:
                # This will now show Sieve compile errors or permission issues
                print(f"  LDA Error: {e.stderr.decode()}", file=sys.stderr)
            
        imap.logout()
        print(f"    Successfully processed {len(uids)} messages.")

    except Exception as e:
        print(f"    Error processing {name}: {e}", file=sys.stderr)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <secrets_dir> [search_filter]")
        sys.exit(1)

    secrets_dir = sys.argv[1]
    # Allow passing "ALL" or "SINCE 01-Jan-2023" as the second argument
    search_filter = sys.argv[2] if len(sys.argv) > 2 else "UNSEEN"

    if not os.path.isdir(secrets_dir):
        print(f"Error: {secrets_dir} is not a directory")
        sys.exit(1)

    for f in sorted(os.listdir(secrets_dir)):
        if f.startswith("gmail-") and f.endswith(".json"):
            fetch_account(os.path.join(secrets_dir, f), search_filter)