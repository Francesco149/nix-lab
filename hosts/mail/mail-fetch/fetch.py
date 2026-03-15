#!/usr/bin/env python3

import imaplib
import json
import mailbox
import os
import sys
import urllib.parse
import urllib.request
import base64
import time

def get_access_token(creds_file):
    with open(creds_file) as f:
        creds = json.load(f)
    resp = urllib.request.urlopen(urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode({
            "client_id":     creds["client_id"],
            "client_secret": creds["client_secret"],
            "refresh_token": creds["refresh_token"],
            "grant_type":    "refresh_token",
        }).encode()
    ))
    return json.loads(resp.read())["access_token"]

def xoauth2_string(user, token):
    s = f"user={user}\x01auth=Bearer {token}\x01\x01"
    return s.encode()  # imaplib handles the base64 itself

def fetch(creds_file, maildir_path):
    name = os.path.basename(creds_file).removeprefix("gmail-").removesuffix(".json")
    email = name

    token = get_access_token(creds_file)
    auth_string = xoauth2_string(email, token)

    imap = imaplib.IMAP4_SSL("imap.gmail.com", 993)
    imap.authenticate("XOAUTH2", lambda _: auth_string)
    imap.select("INBOX")

    _, data = imap.search(None, "UNSEEN")
    uids = data[0].split()
    print(f"{email}: {len(uids)} new messages")

    mdir = mailbox.Maildir(maildir_path, create=False)

    for uid in uids:
        _, msg_data = imap.fetch(uid, "(RFC822)")
        raw = msg_data[0][1]
        msg = mailbox.MaildirMessage(raw)
        msg.set_flags("")
        mdir.add(msg)

    imap.logout()

if __name__ == "__main__":
    secrets_dir = sys.argv[1]
    maildir_path = sys.argv[2]

    for creds_file in sorted(f"{secrets_dir}/{f}" for f in os.listdir(secrets_dir) if f.startswith("gmail-") and f.endswith(".json")):
        try:
            fetch(creds_file, maildir_path)
        except Exception as e:
            print(f"Error fetching {creds_file}: {e}", file=sys.stderr)