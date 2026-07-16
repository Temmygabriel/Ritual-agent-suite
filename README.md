# Ritual Agent Suite

Ten AI agent smart contracts for Ritual Chain (testnet, chain id `1979`), each with a real
practical use case. Built against the official `ritual-dapp-skills` repo — see "Before you
deploy" below.

## Contracts

| # | Contract | Precompiles used | What it does |
|---|----------|-------------------|---------------|
| 1 | `ClauseRiskFlagger` | LLM (0x0802) | Flags predatory/risky clauses in a lease, loan, or contract |
| 2 | `ClaimTriageAssistant` | LLM | Scores insurance claims for priority/plausibility for a human adjuster |
| 3 | `ResumeScreener` | LLM | Scores a resume vs a job spec, with explicit bias guardrails |
| 4 | `ExpenseAnomalyChecker` | LLM | Flags duplicate/inflated/out-of-policy expense line items |
| 5 | `ContentModerator` | LLM | Approves/rejects forum posts before they go live |
| 6 | `PayPerQuestionExpert` | LLM | Pay a small RITUAL fee, get one AI answer — ownerless metered API |
| 7 | `FactChecker` | HTTP (0x0801) + LLM | Fetches live sources, then judges a claim against them |
| 8 | `SentimentWatcher` | HTTP + LLM + Scheduler | Recurring: polls a topic, summarizes sentiment, flags spikes |
| 9 | `PriceAnomalyWatcher` | HTTP + LLM + Scheduler | Recurring: polls a price source, flags scraping errors/manipulation |
| 10 | `OnChainNPC` | LLM | Game NPC that remembers each player's conversation in contract storage |

Every contract inherits `src/lib/RitualBase.sol`, which has:
- Owner controls and a real withdrawal path (RitualWallet → contract → owner wallet)
- `pickLLMExecutor()` / `pickHTTPExecutor()` — call these first (free, read-only) to get an
  executor address, then pass it into whichever request function you're using
- The LLM and HTTP precompile call/decode logic, shared so it's only written once

## Scope note: "persistent" agents

Contracts 8 and 9 achieve "keeps running after you close the tab" using the **Scheduler**
contract (`0x56e7...58B`) to call themselves back on a fixed block cadence, combined with
HTTP + LLM. This is deliberately simpler than Ritual's full Sovereign Agent (`0x080C`) /
Persistent Agent (`0x0820`) precompiles, which require a separate factory deployment, DKMS
key derivation, and heartbeat monitoring — a substantially larger build. If you want true
agent-precompile-based agents later, that's a good follow-on project once these 10 are live.

## Before you deploy — mandatory verification step

This project was built from the official `ritual-dapp-skills` repo
(`https://github.com/ritual-foundation/ritual-dapp-skills`) as of the build date. Ritual
Chain testnet is actively developed — addresses, ABI layouts, and model availability can
change. **Before deploying, re-clone that repo and re-check:**
- `skills/ritual-dapp-contracts/SKILL.md` — system contract addresses, precompile addresses
- `skills/ritual-dapp-llm/SKILL.md` — confirm `zai-org/GLM-4.7-FP8` is still the live
  production model (there was a known, since-likely-fixed TEE cert-registration issue —
  confirm it's clear before relying on LLM calls)
- `https://skills.ritualfoundation.org` and `https://docs.ritualfoundation.org` for anything
  newer than the cloned repo

If anything conflicts with this project's code, the live repo wins — fix the code to match
before deploying.

## Known constants used in this build

| Item | Value |
|---|---|
| Chain ID | `1979` |
| RPC | `https://rpc.ritualfoundation.org` |
| Explorer | `https://explorer.ritualfoundation.org` |
| Faucet | `https://faucet.ritualfoundation.org` |
| RitualWallet | `0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948` |
| TEEServiceRegistry | `0x9644e8562cE0Fe12b4deeC4163c064A8862Bf47F` |
| Scheduler | `0x56e776BAE2DD60664b69Bd5F865F1180ffB7D58B` |
| LLM precompile | `0x0000000000000000000000000000000000000802` |
| HTTP precompile | `0x0000000000000000000000000000000000000801` |
| LLM model | `zai-org/GLM-4.7-FP8` (reasoning model — needs `maxCompletionTokens >= 4096`, `ttl >= 300`) |

## Workflow

1. **Local PC**: unzip this project, open the folder in VS Code.
2. **VS Code terminal**: `git init`, commit, create a GitHub repo, push.
3. **GitHub → Codespaces**: open a codespace on the repo (avoids local Foundry install issues).
4. **Codespaces terminal**: install Foundry, `forge build`, `forge test`.
5. **MetaMask**: fresh testnet-only account, add Ritual network (chain id `1979`), get funds
   from the faucet.
6. **Codespaces terminal**: set up `.env` from `.env.example`, deploy one contract at a time
   with `forge create ... --broadcast`, fund each with `depositForFees()`, then call it.

We'll go through steps 3–6 together, one command at a time, confirming your output before
moving on — same as steps 1–2 will be, right now.

## Security checklist (already handled in the code, verify on first deploy)

- [x] Owner-withdrawal function that sends RITUAL to an actual wallet, not just internal shuffling
- [x] `depositForFees` / RitualWallet integration
- [x] Executors fetched from `TEEServiceRegistry`, never hardcoded
- [x] `hasError` checked before touching `completionData` on every LLM call
- [x] Named structs used for `abi.decode` targets (no bare inline tuples)
- [ ] **You still need to**: verify gas limits are sufficient for your real payloads (raise if
  a tx reverts at 100% gas usage), and confirm the LLM cert-registration issue is resolved on
  your first real call (see "Before you deploy" above)
