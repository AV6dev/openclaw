# Free deep research for Paperclip

A research team where every worker runs on free models. A job starts on NVIDIA's free API. If that is rate-limited it moves to your own Ollama PCs, and if they're all off it runs on the gateway host's own Ollama. Only the planning and final write-up use Claude.

```
Paperclip
 ├─ Research Lead            claude_local (Sonnet)    plans, delegates, writes the report
 ├─ Researcher 1, 2, 3       openclaw_gateway ─┐      run sub-questions in parallel
 └─ Research Checker         openclaw_gateway ─┤
                                               ▼
                             OpenClaw gateway: each job walks the chain until one answers
                               1. NVIDIA Llama 3.3 70B          free, fast, rate-limited
                               2. NVIDIA Nemotron 70B           free, fast, rate-limited
                               3. Ollama pool (via nginx)       free, slow, unlimited
                                    ├─ remote PC 1 ┐ least busy first,
                                    ├─ remote PC 2 ┘ dead PCs skipped
                                    └─ gateway host's Ollama    only when all remotes are down
```

The switch happens inside OpenClaw, within the same job, so Paperclip never sees a failure and nothing needs reassigning. When NVIDIA rate-limits the key, OpenClaw puts it in cooldown, so the jobs that follow go straight to the Ollama pool until NVIDIA recovers.

**Why nginx:** it spreads jobs across the PCs by load, skips a PC that's switched off or missing the model within the same request, and keeps the gateway host as the final backup. The pool never fails as long as the gateway host is up.

OpenClaw builds from this branch also move to the next model when a host can't be reached (for example, if nginx itself is down). Older OpenClaw releases stop the job instead, so nginx is what makes it reliable on those.

## Files

| File | Goes to |
| --- | --- |
| `.env.example` | `~/.openclaw/.env` on the gateway host |
| `openclaw/research-agents.json5` | `~/.openclaw/research-agents.json5` |
| `openclaw/workspaces/researcher/AGENTS.md` | `~/.openclaw/workspace-researcher/AGENTS.md` |
| `openclaw/workspaces/research-checker/AGENTS.md` | `~/.openclaw/workspace-research-checker/AGENTS.md` |
| `ollama/nginx-ollama-pool.conf` | `/etc/nginx/conf.d/ollama-pool.conf` on the gateway host |
| `ollama/setup-worker-linux.sh` | Run on each remote Linux PC |
| `ollama/check-pool.sh` | Run on the gateway host to see which workers are up |
| `paperclip/agents.json5` | Settings for the Paperclip agents |
| `paperclip/research-lead.md` | Instructions file for the Research Lead |

## 1. Get the keys

- **NVIDIA** (free): sign in at https://build.nvidia.com and create an API key (`nvapi-...`).
- **Brave Search** (free tier): https://brave.com/search/api/

## 2. Connect the machines (recommended: Tailscale)

Ollama has no password. Anyone who can reach its port can use it. Put the gateway host and every worker PC on [Tailscale](https://tailscale.com) (free for personal use), so the workers are only reachable from your own machines, including over the internet.

## 3. Set up each remote PC as an Ollama worker

**Linux:**

```bash
sudo ./ollama/setup-worker-linux.sh            # binds to the PC's Tailscale IP
```

It installs Ollama, makes it listen on the Tailscale IP, pulls `llama3.1:8b`, and prints the line to add to the nginx config.

**Windows or macOS:**

1. Install Ollama from https://ollama.com.
2. Set the environment variable `OLLAMA_HOST` to `<tailscale-ip>:11434`. On Windows use System Properties → Environment Variables. On macOS run `launchctl setenv OLLAMA_HOST <tailscale-ip>:11434`.
3. Quit and restart Ollama, then run `ollama pull llama3.1:8b`.

**Which PCs are worth it:** `llama3.1:8b` with the 32k context needs about 16 GB of RAM. A GPU with 8 GB+ makes it much faster. On CPU only, expect a job to take 5–20 minutes. Every worker must have the same model pulled.

## 4. Set up the gateway host

```bash
# Local Ollama: the last-resort worker
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.1:8b

# nginx pool
sudo apt install nginx
sudo cp ollama/nginx-ollama-pool.conf /etc/nginx/conf.d/ollama-pool.conf
sudo nano /etc/nginx/conf.d/ollama-pool.conf   # replace the example server lines with your workers
sudo nginx -t && sudo systemctl reload nginx
./ollama/check-pool.sh                          # UP / DOWN / NO MODEL for each worker

# OpenClaw
cp .env.example ~/.openclaw/.env && chmod 600 ~/.openclaw/.env   # then fill in the keys
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

**If your config has no `agents.list` yet**, add your main agent first as well. Otherwise `researcher` becomes the default agent for your chat channels:

```json5
agents: { list: [{ id: "main", default: true }] },
```

The include also sets `agents.defaults.maxConcurrent: 4` (so the Researchers can run at once) and `agents.defaults.timeoutSeconds: 1800` (so slow local runs can finish). If your own config already sets either of these, yours wins, so check them.

Paperclip connects over the network, so keep token auth on and bind where Paperclip can reach it. Loopback is fine if Paperclip runs on the same machine; use `tailnet` otherwise:

```bash
openclaw config set gateway.auth.mode token
openclaw config get gateway.auth.token      # copy this for Paperclip
```

Restart the gateway and test each tier:

```bash
openclaw agents list
openclaw agent --agent researcher --message "What is the current UK VAT rate? Follow your steps."
```

To test the Ollama tier on its own, temporarily blank `NVIDIA_API_KEY` in `~/.openclaw/.env`, restart, and run the same command. It should still answer, just slower.

## 5. Set up Paperclip

Create the agents using the values in `paperclip/agents.json5`:

1. **Research Lead:** adapter `claude_local`, instructions file `paperclip/research-lead.md`.
2. **Researcher 1, Researcher 2, Researcher 3:** identical settings, adapter `openclaw_gateway`, `payloadTemplate` `{ "agentId": "researcher" }`. Add more if you add more worker PCs, and name them in `research-lead.md`.
3. **Research Checker:** adapter `openclaw_gateway`, `payloadTemplate` `{ "agentId": "research-checker" }`.
4. All of them: gateway URL `ws://<gateway-host>:18789`, the gateway token, timer off (`intervalSec: 0`), wake on assignment on, and the timeouts shown (about 30 minutes, for slow local runs).

## 6. Run it

Create an issue assigned to the Research Lead, for example:

> Research the UK market for managed WordPress hosting for small agencies: main providers, pricing ranges, and what agencies complain about. UK sources, last 2 years.

## Adding paid accounts later

Put the key in `~/.openclaw/.env` and add the model to both `fallbacks` lists in `research-agents.json5`, **before** `ollama-pool/...`, so it's used ahead of the slow tier. See https://docs.openclaw.ai/providers for key names and model id formats.

Use one account per provider. Opening several free accounts with the same provider to multiply the free allowance usually breaks that provider's terms and can get all of them banned.

## Tuning

- **Output cut off:** NVIDIA models are capped at 4,096 output tokens. The 400-word limit in the Researcher's `AGENTS.md` keeps it well under.
- **Ollama runs fail with context errors:** a job didn't fit in 32k. Lower `tools.web.fetch.maxChars` in `research-agents.json5`, or raise `contextWindow` if your PCs have the RAM.
- **Researcher loops on tools:** loop detection stops it. Small local models are the most likely to loop; tighten the step counts in its `AGENTS.md`.
- **Everything is landing on Ollama:** NVIDIA is rate-limiting you. Spread research over time, or add a paid account ahead of the pool.
- **Reports feel thin:** raise the Lead to Opus or `effort: "high"` first. Most of the quality comes from the plan and the write-up.
