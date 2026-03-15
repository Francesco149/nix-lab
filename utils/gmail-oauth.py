import urllib.parse, webbrowser, urllib.request, json, sys

if len(sys.argv) != 3:
    print(f"usage: {sys.argv[0]} <credentials.json> <account-name>")
    sys.exit(1)

with open(sys.argv[1]) as f:
    creds = json.load(f)

# Google's downloaded credentials JSON nests everything under "installed" or "web"
app = creds.get("installed") or creds.get("web")
client_id = app["client_id"]
client_secret = app["client_secret"]
account_name = sys.argv[2]
scope = "https://mail.google.com/"

auth_url = (
    "https://accounts.google.com/o/oauth2/auth?"
    + urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
        "response_type": "code",
        "scope": scope,
        "access_type": "offline",
    })
)
webbrowser.open(auth_url)
code = input("Paste the code: ")

resp = urllib.request.urlopen(urllib.request.Request(
    "https://oauth2.googleapis.com/token",
    data=urllib.parse.urlencode({
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": "urn:ietf:wg:oauth:2.0:oob",
        "grant_type": "authorization_code",
    }).encode()
))

tokens = json.loads(resp.read())

out = {
    "client_id": client_id,
    "client_secret": client_secret,
    "refresh_token": tokens["refresh_token"],
}

filename = f"gmail-{account_name}.json"
with open(filename, "w") as f:
    json.dump(out, f, indent=2)

print(f"Saved to {filename}")
