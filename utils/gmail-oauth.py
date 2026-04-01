import urllib.parse, webbrowser, urllib.request, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

# Settings
PORT = 8080
REDIRECT_URI = f"http://localhost:{PORT}"
SCOPE = "https://mail.google.com/"

if len(sys.argv) != 3:
    print(f"usage: {sys.argv[0]} <credentials.json> <account-name>")
    sys.exit(1)

# Helper class to catch the redirect code
class OAuthCodeHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        if "code" in params:
            self.server.auth_code = params["code"][0]
            self.wfile.write(b"<h1>Authentication successful!</h1><p>You can close this window and return to the terminal.</p>")
        else:
            self.wfile.write(b"<h1>Error</h1><p>No code found in the redirect.</p>")

def get_tokens(creds_path, account_name):
    with open(creds_path) as f:
        creds = json.load(f)

    app = creds.get("installed") or creds.get("web")
    client_id = app["client_id"]
    client_secret = app["client_secret"]

    # 1. Build the Auth URL
    auth_url = (
        "https://accounts.google.com/o/oauth2/auth?"
        + urllib.parse.urlencode({
            "client_id": client_id,
            "redirect_uri": REDIRECT_URI,
            "response_type": "code",
            "scope": SCOPE,
            "access_type": "offline",
            "prompt": "consent", # Forces Google to give a refresh token
        })
    )

    # 2. Start temporary server and open browser
    server = HTTPServer(("localhost", PORT), OAuthCodeHandler)
    print(f"Opening browser for authentication...")
    webbrowser.open(auth_url)
    
    # Wait for the user to login and the redirect to hit our server
    server.handle_request() 
    code = server.auth_code

    # 3. Exchange code for tokens
    resp = urllib.request.urlopen(urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode({
            "code": code,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": REDIRECT_URI,
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

    print(f"\nSaved to {filename}")

if __name__ == "__main__":
    get_tokens(sys.argv[1], sys.argv[2])
