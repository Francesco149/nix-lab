# Oh My Pi (omp) & AI Models Reference

This document is the single reference for model configuration, authentication,
token rotation, and vision routing in `nix-lab`.

---

## 1. Overview & Architecture

* **Harness**: `omp` ([can1357/oh-my-pi](https://github.com/can1357/oh-my-pi)) on `wslop`.
* **Nix Modules**: `hosts/wslop/hm/omp.nix` packages `omp` and declaratively syncs
  configuration files on Home Manager activation:
  * Declarative templates: `hosts/wslop/hm/omp-config.yml`, `omp-models.yml`, `APPEND_SYSTEM.md`.
  * Runtime files: `~/.omp/agent/config.yml`, `~/.omp/agent/models.yml`, `~/.omp/agent/.env`,
    and the SQLite credential store at `~/.omp/agent/agent.db`.
* **API Secrets**: Kept outside the Nix store in `~/.omp/agent/.env` (e.g.
  `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, `ZAI_API_KEY`).
* **Default Roles** (`~/.omp/agent/config.yml`):
  * Text roles (`default`, `smol`, `slow`, `plan`, `commit`, `task`): `deepseek/deepseek-v4-flash`.
  * Vision role (`vision`): `openrouter/qwen/qwen3.7-flash`.
  * Thinking default: `defaultThinkingLevel: high`. Requesting "ultrathink" in a
    prompt pushes thinking to `xhigh` ("max").

---

## 2. Model Providers & Authentication

### A. Google Antigravity (Gemini Pro Subscription)

The subscription route connects to Google's Antigravity consumer backend
(`daily-cloudcode-pa.googleapis.com`) using your Google AI Pro subscription
rather than the metered API.

* **Initial Login**:
  1. In `omp`, run:
     ```text
     /login google-antigravity
     ```
  2. A browser opens on port `51121` (OAuth PKCE). Sign in with your Google account.
  3. If redirect fails on a remote session, copy the redirect URL and run:
     ```text
     /login <redirect-url>
     ```
* **Selectable Models**:
  * `google-antigravity/gemini-3.1-pro` (default)
  * `google-antigravity/gemini-3.5-flash`
  * `google-antigravity/gemini-3.7-flash`
  * `google-antigravity/claude-sonnet-4-6` / `claude-opus-4-6`
* **Checking Quota**:
  ```bash
  omp usage
  # Or filtered:
  omp usage --provider google-antigravity
  ```

---

### B. Multi-Account Management & Token Rotation (`omp-token`)

When running secondary/long-term Antigravity accounts (e.g. a 3-month refresh
token account alongside your primary subscription), credentials are stored in
`~/.omp/agent/agent.db` (`auth_credentials`).

* **Account Ranking**: `omp` automatically balances accounts by usage drain
  urgency ("use it or lose it"). The account whose quota expires sooner ranks
  first; accounts with $\ge 90\%$ used quota rank last.
* **CLI Helper (`omp-token`)**:
  * List registered accounts:
    ```bash
    omp-token list
    ```
  * Add a new account via refresh token:
    ```bash
    omp-token add <refresh-token>
    ```
    *(Exchanges the token against omp's OAuth client, discovers the account email and Antigravity project, and injects the credential row into `agent.db`)*.
  * Remove an expired account:
    ```bash
    omp-token remove <email>
    ```
    *(Refuses to drop the primary protected account or the last remaining account)*.
* **Token Rotation Runbook**:
  1. Check status: `omp-token list`
  2. Drop expired token: `omp-token remove <email-of-expired-account>`
  3. Add fresh token: `omp-token add <new-refresh-token>`
  4. Confirm quotas: `omp usage`

---

### C. Z.AI / GLM Coding Plan (Zhipu AI Subscriptions)

Oh My Pi natively supports Z.AI subscriptions (GLM Coding Plan Lite, Pro, etc.)
and routes requests to Z.AI's Coding PaaS endpoints
(`https://api.z.ai/api/anthropic` and `https://api.z.ai/api/coding/paas/v4`).

* **Option 1: Browser OAuth Sign-In (Recommended)**:
  1. In `omp`, run:
     ```text
     /login zai-coding-plan
     ```
  2. Sign in via browser on `https://chat.z.ai/api/oauth/authorize` (port `54548` callback).
  3. `omp` completes the token exchange, auto-mints an `oh-my-pi` API key, and
     persists it under provider `zai`.
* **Option 2: Direct Dashboard API Key**:
  1. Copy your API key from [https://z.ai/manage-apikey/apikey-list](https://z.ai/manage-apikey/apikey-list).
  2. Run `/login zai` or add to `~/.omp/agent/.env`:
     ```bash
     ZAI_API_KEY=sk-...
     ```
* **Selectable Models**:
  * `zai/glm-5.2` (1M context, full reasoning support)
  * `zai/glm-5.3` (or `openrouter/z-ai/glm-5.3`)
  * `zai/glm-5.1`
  * `zai/glm-4.7`
* **Domestic China Alternative**:
  * Provider: `zhipu-coding-plan` (`https://open.bigmodel.cn/api/coding/paas/v4`)
  * Auth: `/login zhipu-coding-plan` or `ZHIPU_API_KEY=...` in `~/.omp/agent/.env`.

---

### D. Other Providers

* **DeepSeek Native**:
  * Set `DEEPSEEK_API_KEY=sk-...` in `~/.omp/agent/.env` (or `/login deepseek`).
  * Models: `deepseek/deepseek-v4-flash`, `deepseek/deepseek-v4-pro`.
* **Anthropic Claude**:
  * Set `ANTHROPIC_API_KEY=sk-ant-...` or run `/login anthropic` (OAuth port 54545).
  * Models: `anthropic/claude-sonnet-4-6`, `anthropic/claude-opus-4-6`.
* **OpenRouter**:
  * Set `OPENROUTER_API_KEY=sk-or-...` in `~/.omp/agent/.env` (or `/login openrouter`).
  * Models: `openrouter/qwen/qwen3.7-flash` (vision default), any OpenRouter catalog ID.

---

## 3. Vision Subsystem & State Protocol

* **Default**: OpenRouter `qwen/qwen3.7-flash` (cheapest verified; ~2530 tok/image).
* **Local Fallback**: `qwen3.5-9b` on `lame` (7800XT, port 8080, `gpu-switch vision`).
* **CLI Wrapper**: `/usr/local/bin/vision`
  * Inspect image: `vision /path/to/image.png`
  * Probe without waking host: `vision --check`
  * Video processing (chunk+join): `vision --video /path/to/clip.mp4`

### State Protocol for Agents

When `vision` or `inspect_image` executes:

| State | Exit Code | Meaning & Required Action |
| --- | --- | --- |
| `VISION_STATE=ok` | 0 | Success (via OpenRouter or running local VLM). Process output. |
| `VISION_STATE=switch` | 3 | OpenRouter failed AND `lame` is up, but GPU is running another task. **Ask the human to confirm** `ssh root@lame gpu-switch run vision` before switching (thrash guard). Do not retry in a loop. |
| `VISION_STATE=down` | 4 | OpenRouter failed AND `lame` is unreachable even after automatic wake. **Continue working without vision** (OCR/read/text-only) and notify the human. |

### Vision vs. Text-Only Models

1. **Vision-Capable Models (Gemini, Claude)**:
   * Native image support (`input: [text, image]`).
   * Image attachments and `read` tool outputs are sent directly to the model.
   * `inspect_image` is deactivated.
2. **Text-Only Models (DeepSeek)**:
   * Attached images are auto-described into `<image path="local://...">` blocks
     using the configured `vision` role.
   * `inspect_image` is mounted under `xd://inspect_image` for ad-hoc inspection:
     ```json
     {"path": "/tmp/shot.png", "question": "What is shown in the top right?"}
     ```

---

## 4. Coding Harness Experiments (`/opt/src/haruness`)

* The lab's agentic coding harness experimentation lives in sibling repo `/opt/src/haruness`.
* **Detached Execution on `lame`**:
  * Start watcher service: `../haruness/scripts/lame-watch.sh up [LOGFILE]`
  * Check status: `../haruness/scripts/lame-watch.sh status`
  * View logs: `../haruness/scripts/lame-watch.sh log [N]`
* **wslop Environment**:
  * All tools (bun, python3, matplotlib, dev shells) are available via `nix develop`:
    ```bash
    cd /opt/src/haruness && nix develop
    ```
