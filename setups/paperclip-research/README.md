# Low-cost deep research for Paperclip

A three-agent research team where the reading and summarising runs on free NVIDIA models through OpenClaw, and only the planning and final write-up use Claude.

```
Paperclip
 ├─ Research Lead      claude_local (Sonnet)      plans, delegates, writes the report
 ├─ Researcher         openclaw_gateway ─► OpenClaw agent "researcher"
 │                       NVIDIA Llama 3.3 70B (free) → Nemotron 70B (free) → Haiku
 └─ Research Checker   openclaw_gateway ─► OpenClaw agent "research-checker"
                         Nemotron 70B (free) → Llama 3.3 70B (free) → Haiku
```

A typical report is 3–6 Researcher runs, 1 Checker run and 2–3 short Lead runs. The Lead never reads web pages, only the compact notes, which is where the saving comes from.

## Files

| File | Goes to |
| --- | --- |
| `.env.example` | `~/.openclaw/.env` on the gateway host |
| `openclaw/research-agents.json5` | `~/.openclaw/research-agents.json5` |
| `openclaw/workspaces/researcher/AGENTS.md` | `~/.openclaw/workspace-researcher/AGENTS.md` |
| `openclaw/workspaces/research-checker/AGENTS.md` | `~/.openclaw/workspace-research-checker/AGENTS.md` |
| `paperclip/agents.json5` | Settings for the three Paperclip agents |
| `paperclip/research-lead.md` | Instructions file for the Research Lead |

## 1. Get the keys

- **NVIDIA** (free): sign in at https://build.nvidia.com and create an API key (`nvapi-...`).
- **Brave Search** (free tier): https://brave.com/search/api/
- **Anthropic** (optional): only used if both NVIDIA models fail. Without it, a failed run just fails instead of spending money.

## 2. Set up OpenClaw (gateway host)

```bash
cp .env.example ~/.openclaw/.env           # then fill in the keys
chmod 600 ~/.openclaw/.env
cp openclaw/research-agents.json5 ~/.openclaw/
mkdir -p ~/.openclaw/workspace-researcher ~/.openclaw/workspace-research-checker
cp openclaw/workspaces/researcher/AGENTS.md ~/.openclaw/workspace-researcher/
cp openclaw/workspaces/research-checker/AGENTS.md ~/.openclaw/workspace-research-checker/
```

Add one line at the top level of `~/.openclaw/openclaw.json`:

```json5
{
  $include: "./research-agents.json5",
  // ...your existing config
}
```

**If your config has no `agents.list` yet**, also add your main agent first, otherwise `researcher` becomes the default agent for your chat channels:

```json5
agents: { list: [{ id: "main", default: true }] },
```

Paperclip connects over the network, so the gateway needs token auth and a bind Paperclip can reach. If Paperclip runs on the same machine, the default `loopback` bind is fine. Otherwise use `tailnet` or `lan` and keep the token set:

```bash
openclaw config set gateway.auth.mode token
openclaw config get gateway.auth.token      # copy this for Paperclip
```

Restart the gateway, then check the agents and the NVIDIA key:

```bash
openclaw agents list
openclaw agent --agent researcher --message "What is the current UK VAT rate? Follow your steps."
```

## 3. Set up Paperclip

Create the three agents using the values in `paperclip/agents.json5`:

1. **Research Lead:** adapter `claude_local`, instructions file `paperclip/research-lead.md`.
2. **Researcher** and **Research Checker:** adapter `openclaw_gateway`, URL `ws://<gateway-host>:18789`, the gateway token, and `payloadTemplate` `{ "agentId": "researcher" }` / `{ "agentId": "research-checker" }`. Set both to report to the Research Lead.
3. Heartbeat on all three: timer off (`intervalSec: 0`), wake on assignment on. Nothing runs unless there's a research task.
4. Set each `budgetMonthlyCents` as shown.

## 4. Run it

Create an issue assigned to the Research Lead, for example:

> Research the UK market for managed WordPress hosting for small agencies: main providers, pricing ranges, and what agencies complain about. UK sources, last 2 years.

## Adding your cheap paid accounts

For each £10/month account, put its key in `~/.openclaw/.env` and add its model to both `fallbacks` lists in `research-agents.json5`, before the `anthropic/...` line. See https://docs.openclaw.ai/providers for the key name and model id format for each provider. A flat-rate plan can also go in as `primary` if its limits are more generous than NVIDIA's.

Use one account per provider. Opening several free accounts with the same provider to multiply the free allowance usually breaks that provider's terms and can get all of them banned.

## Tuning

- **Researcher runs out of tokens mid-answer:** NVIDIA models are capped at 4,096 output tokens in OpenClaw. The 400-word limit in its `AGENTS.md` keeps it well under; don't raise that much.
- **Researcher loops on tools:** loop detection is on and will stop it. Tighten the step counts in its `AGENTS.md` if it happens often.
- **Too many runs fall back to Haiku:** you're hitting NVIDIA rate limits. Add a cheap paid account ahead of Haiku.
- **Reports feel thin:** raise the Lead to Opus or `effort: "high"` before changing the free agents. Most of the quality comes from the plan and the write-up.
