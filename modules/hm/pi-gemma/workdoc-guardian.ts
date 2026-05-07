/**
 * workdoc-guardian.ts
 *
 * Pi extension for Gemma4 A4B coding sessions.
 *
 * Provides:
 *   1. Session start → inject WORKDOC.md restore prompt
 *   2. Periodic working-doc update reminders (every REMINDER_INTERVAL turns)
 *   3. Stuck detection → steer the model when repeated tool calls detected
 *   4. Context budget warning → remind before Pi's compaction fires
 *   5. `spawn_subagent` tool → focused file analysis without bloating context
 *   6. `/workdoc` command → init / show working document
 *
 * Configuration via environment variables (set by Nix module):
 *   GEMMA_OLLAMA_URL   e.g. http://localhost:11434/v1   (default)
 *   GEMMA_MODEL_ID     e.g. gemma4                      (default)
 *   GEMMA_SUBAGENT_MAX_TOKENS   default 1024
 *
 * Event names verified against Pi v0.70.x — if Pi upgrades event names,
 * check: https://pi.dev/docs/latest/extensions#events
 */

import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import * as fs from "fs";
import * as path from "path";

// ── Configuration ─────────────────────────────────────────────────────────────

const OLLAMA_URL     = process.env.GEMMA_OLLAMA_URL   ?? "http://localhost:11434/v1";
const MODEL_ID       = process.env.GEMMA_MODEL_ID     ?? "gemma4";
const SUBAGENT_TOKENS = Number(process.env.GEMMA_SUBAGENT_MAX_TOKENS ?? "1024");

/** Inject a WORKDOC update reminder every N agent turns. */
const REMINDER_INTERVAL = 8;

/** After this many turns, warn the user to wrap up the session. */
const WRAP_UP_TURN = 17;

/** How many recent tool-call fingerprints to track for stuck detection. */
const STUCK_WINDOW = 4;

/** If the same fingerprint appears ≥ this many times in STUCK_WINDOW, we're stuck. */
const STUCK_THRESHOLD = 2;

// ── Per-session state (reset on sessionReady) ─────────────────────────────────

interface State {
  turnCount: number;
  remindedAt: Set<number>;
  recentFingerprints: string[];
  stuckWarningFired: boolean;
  contextWarningFired: boolean;
}

function freshState(): State {
  return {
    turnCount: 0,
    remindedAt: new Set(),
    recentFingerprints: [],
    stuckWarningFired: false,
    contextWarningFired: false,
  };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function workdocPath(cwd: string): string {
  return path.join(cwd, "WORKDOC.md");
}

function workdocExists(cwd: string): boolean {
  return fs.existsSync(workdocPath(cwd));
}

/**
 * Fingerprint a tool call for stuck detection.
 * We only look at name + first 120 chars of args so minor variations
 * (e.g. slightly different grep patterns) don't reset the counter.
 */
function fingerprint(toolName: string, args: unknown): string {
  return `${toolName}:${JSON.stringify(args ?? "").slice(0, 120)}`;
}

/**
 * Returns true if the recent fingerprint window shows STUCK_THRESHOLD
 * occurrences of the same fingerprint — i.e., the model is looping.
 */
function isStuck(fps: string[]): boolean {
  if (fps.length < STUCK_THRESHOLD) return false;
  const counts: Record<string, number> = {};
  for (const fp of fps) {
    counts[fp] = (counts[fp] ?? 0) + 1;
    if (counts[fp] >= STUCK_THRESHOLD) return true;
  }
  return false;
}

/**
 * Call the local model API for a focused analysis sub-call.
 * Returns the model's text response.
 */
async function callSubagent(systemPrompt: string, userPrompt: string): Promise<string> {
  const resp = await fetch(`${OLLAMA_URL}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODEL_ID,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user",   content: userPrompt   },
      ],
      stream: false,
      max_tokens: SUBAGENT_TOKENS,
      temperature: 0.2,
    }),
  });
  if (!resp.ok) {
    throw new Error(`Subagent call failed: ${resp.status} ${await resp.text()}`);
  }
  const data = await resp.json() as {
    choices: Array<{ message: { content: string } }>;
  };
  return data.choices[0]?.message?.content ?? "(empty response)";
}

// ── Extension entry point ─────────────────────────────────────────────────────

export default function(pi: ExtensionAPI) {
  let state = freshState();

  // ── 1. Session ready → restore WORKDOC if it exists ─────────────────────────
  //
  // "sessionReady" fires once after Pi loads a session (new or resumed).
  // We inject a user message so the model reads WORKDOC.md on first turn.
  // Pi will queue it; the model responds when the user sends their first
  // actual message.
  //
  // Note: in Pi the agent loop doesn't auto-start — the model only responds
  // when the user sends something. Injecting here primes the context but
  // the model won't run until the user types.

  pi.on("sessionReady", async (ctx: ExtensionContext) => {
    state = freshState();

    if (workdocExists(ctx.cwd)) {
      // Ask model to restore state from file
      await pi.sendUserMessage(
        "[GUARDIAN] Session started. Read WORKDOC.md now and restore your " +
        "task state before anything else. Acknowledge with a one-line summary " +
        "of where we left off.",
        { followUp: true }
      );
    } else {
      // Silently notify the human user via TUI — no model turn needed
      ctx.ui.notify(
        "💡 Tip: run /workdoc init to create WORKDOC.md for this project. " +
        "Load /skill:gemma-coding to start a structured coding session."
      );
    }
  });

  // ── 2. After each agent turn: reminders, stuck detection, context warning ────
  //
  // "agentEnd" fires after the model finishes a turn (text response emitted,
  // all tool calls in the turn resolved).

  pi.on("agentEnd", async (ctx: ExtensionContext) => {
    state.turnCount++;

    // Context budget warning — fire once when we cross 65%
    const usage = ctx.getContextUsage?.();
    if (
      usage &&
      !state.contextWarningFired &&
      usage.used / usage.total > 0.65
    ) {
      state.contextWarningFired = true;
      await pi.sendUserMessage(
        `[GUARDIAN] Context at ${Math.round((usage.used / usage.total) * 100)}% — ` +
        "Pi will compact soon. Update WORKDOC.md thoroughly NOW: mark steps [done], " +
        "capture all Findings and Decisions. Anything not in WORKDOC.md will be lost.",
        { followUp: true }
      );
      return; // skip other reminders this turn — context warning takes priority
    }

    // Periodic working-doc update reminder
    const shouldRemind =
      state.turnCount > 0 &&
      state.turnCount % REMINDER_INTERVAL === 0 &&
      !state.remindedAt.has(state.turnCount);

    if (shouldRemind) {
      state.remindedAt.add(state.turnCount);
      await pi.sendUserMessage(
        "[GUARDIAN] Update WORKDOC.md: mark completed steps [done], add new " +
        "findings, log any decisions. Keep it brief. Acknowledge with 'Updated.'",
        { followUp: true }
      );
    }

    // Session wrap-up warning (soft — suggest delegating remaining work)
    if (state.turnCount === WRAP_UP_TURN) {
      await pi.sendUserMessage(
        "[GUARDIAN] You're at turn 17 — update WORKDOC.md thoroughly and wrap " +
        "up the current step. If work remains, leave clear notes in the Plan " +
        "section so the next session can resume cleanly.",
        { followUp: true }
      );
    }
  });

  // ── 3. Tool call hook — stuck detection ─────────────────────────────────────
  //
  // "beforeToolCall" fires before each tool execution.
  // Return the call unmodified to allow it; throw to block it.
  // We use this to track fingerprints and detect loops.

  pi.on("beforeToolCall", async (ctx: ExtensionContext, call: { name: string; args: unknown }) => {
    const fp = fingerprint(call.name, call.args);

    state.recentFingerprints.push(fp);
    if (state.recentFingerprints.length > STUCK_WINDOW) {
      state.recentFingerprints.shift();
    }

    if (!state.stuckWarningFired && isStuck(state.recentFingerprints)) {
      state.stuckWarningFired = true;
      state.recentFingerprints = []; // reset to avoid repeated warnings

      // Inject a steering message — Pi sends this immediately, interrupting
      // the current generation so the model sees it before the next tool call.
      await pi.sendUserMessage(
        "[GUARDIAN] You've repeated the same command. You are stuck. STOP. " +
        "Update WORKDOC.md with what you know so far, then choose a " +
        "completely different approach or ask for clarification.",
        { steer: true }
      );
    } else {
      state.stuckWarningFired = false;
    }

    return call; // allow the call
  });

  // ── 4. spawn_subagent tool ───────────────────────────────────────────────────
  //
  // Delegates focused file analysis to a fresh model call.
  // The orchestrator asks a specific question; the file content is passed
  // directly to the sub-call — it never enters the main context window.
  //
  // This is the Pi equivalent of the ollama-proxy's spawn_agent tool.

  pi.registerTool({
    name: "spawn_subagent",
    description:
      "Focused analysis: ask a specific question about one or more files " +
      "without loading them into main context. " +
      "GOOD: interface assessment, cross-file compatibility check, understanding " +
      "complex logic, SPEC gap analysis. " +
      "BAD: finding symbols (→ bash: git grep), reading a function (→ bash: sed -n), " +
      "listing files (→ bash: git ls-files). " +
      "Always include context. End prompt with 'Be as brief as possible, no preamble.'",
    schema: Type.Object({
      prompt: Type.String({
        description:
          "Focused question. End with: 'Be as brief as possible, no preamble.'",
      }),
      files: Type.Array(
        Type.String({ description: "Absolute file path" }),
        {
          description: "1–3 files only. More than 3 defeats the purpose.",
          minItems: 1,
          maxItems: 3,
        }
      ),
      context: Type.Optional(
        Type.String({
          description:
            "1–2 sentence summary of the current task, for grounding the sub-agent.",
        })
      ),
    }),
    execute: async (args: { prompt: string; files: string[]; context?: string }) => {
      const { prompt, files, context } = args;

      // Read each file
      const fileParts = files.map((f) => {
        try {
          const content = fs.readFileSync(f, "utf-8");
          const lines = content.split("\n");
          const truncated = lines.length > 400
            ? lines.slice(0, 400).join("\n") + "\n... (truncated to 400 lines)"
            : content;
          return `<file path="${f}">\n${truncated}\n</file>`;
        } catch {
          return `<file path="${f}">ERROR: could not read this file</file>`;
        }
      });

      const systemPrompt = context
        ? `You are a focused code analysis assistant. Context: ${context}`
        : "You are a focused code analysis assistant.";

      const userPrompt =
        fileParts.join("\n\n") +
        "\n\n" +
        prompt +
        "\n\nBe as brief as possible, no preamble.";

      try {
        return await callSubagent(systemPrompt, userPrompt);
      } catch (err) {
        return `spawn_subagent error: ${String(err)}`;
      }
    },
  });

  // ── 5. /workdoc command ──────────────────────────────────────────────────────
  //
  // Lets the user manage the working document from within Pi.
  // /workdoc        → show summary (first 600 chars)
  // /workdoc init   → create empty WORKDOC.md
  // /workdoc load   → inject WORKDOC.md content as a user message so the
  //                   model can restore its state mid-session

  pi.registerCommand("workdoc", {
    description: "Manage the session working document (WORKDOC.md). " +
      "Usage: /workdoc | /workdoc init | /workdoc load",
    handler: async (args: string[], ctx: ExtensionContext) => {
      const wp = workdocPath(ctx.cwd);
      const sub = args[0] ?? "";

      if (sub === "init") {
        if (fs.existsSync(wp)) {
          ctx.ui.notify("WORKDOC.md already exists — not overwriting.");
          return;
        }
        const template = [
          "# Working Document",
          "",
          "## Project",
          "",
          "## Task",
          "",
          "## Scope",
          "",
          "## Findings",
          "",
          "## Plan",
          "",
          "## Decisions",
          "",
          "## Open Questions",
          "",
        ].join("\n");
        fs.writeFileSync(wp, template, "utf-8");
        ctx.ui.notify("WORKDOC.md created. Load /skill:gemma-coding to begin.");
        return;
      }

      if (sub === "load") {
        if (!fs.existsSync(wp)) {
          ctx.ui.notify("No WORKDOC.md found. Run /workdoc init first.");
          return;
        }
        const content = fs.readFileSync(wp, "utf-8");
        await pi.sendUserMessage(
          "[GUARDIAN] Working document state:\n\n" + content +
          "\n\nRestore your task state from this. Acknowledge with a one-line " +
          "summary of where we are.",
          { followUp: true }
        );
        return;
      }

      // Default: show summary in UI
      if (!fs.existsSync(wp)) {
        ctx.ui.notify(
          "No WORKDOC.md found in " + ctx.cwd + ". Run /workdoc init to create one."
        );
        return;
      }
      const content = fs.readFileSync(wp, "utf-8");
      const preview = content.length > 600
        ? content.slice(0, 600) + "\n... (truncated — see full file with `read`)"
        : content;
      ctx.ui.notify(preview);
    },
  });
}
