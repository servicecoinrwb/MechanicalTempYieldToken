# 💸 MTYLD Money Flow  
**Mechanical Temp Yield Vault (Arbitrum One)**  
Earn from Real Revenue — Powered by HVAC.

---

## ⚙️ Overview

The **MTYLD Vault** converts real HVAC revenue into on-chain yield.  
Users mint MTYLD with USDC, Mechanical Temp injects real revenue,  
and holders redeem MTYLD for their share of the treasury.

---

## 🧭 Flow Summary

```
User (USDC) 
   │  (mint)
   ▼
Vault Contract (MTYLD)
   ├─► Take mint fee (mintFeeBps) ─► feeRecipient
   └─► Net USDC added to treasuryActiveUSDC
           │
           │  (time)
           ▼
    Treasury (USDC backing)
           │
           │  Owner injects revenue (injectRevenue):
           │   - USDC moves into contract
           │   - Marked as pendingRevenueUSDC
           │   - Excluded from NAV until delay elapses
           │
           │  After navDelaySec (applyPendingRevenue):
           └─► pendingRevenueUSDC → active treasury (raises NAV)
           
           ▲
           │
User (redeem MTYLD)
   │
   └─ Vault computes USDC owed at current NAV:
         ├─ Check active treasury ≥ gross redemption USDC
         ├─ Take redeem fee (redeemFeeBps) ─► feeRecipient
         └─ Pay net USDC to user
```

---

## 🧾 Mint Flow

1. User approves USDC to the vault.  
2. Calls `mint(usdcAmount, minMTYLD)`.  
3. Contract:
   - Calculates **mint fee** → sends to `feeRecipient`.  
   - Converts remaining USDC to MTYLD based on `pricePerToken()`.  
   - Mints MTYLD to user.

Result:  
Treasury grows, and feeRecipient receives USDC.

---

## 💰 Redeem Flow

1. User calls `redeem(mtyldAmount, minUSDC)`.  
2. Contract:
   - Burns MTYLD.  
   - Calculates gross USDC value at NAV.  
   - Sends **redeem fee** to `feeRecipient`.  
   - Pays **net USDC** to user.

Result:  
Vault USDC decreases, feeRecipient receives USDC.

---

## 🧮 Revenue Injection

- Owner calls `injectRevenue(usdcAmount)`.  
- USDC enters the vault but is held as **pendingRevenueUSDC**.  
- NAV delay (`navDelaySec`) prevents instant front-running.  
- After delay, anyone may call `applyPendingRevenue()` to move it into the active treasury.  
- This raises the **NAV** for all holders.

---

## 🪙 NAV & Pricing

| Term | Description |
|------|--------------|
| `pricePerToken()` | Active USDC (scaled to 18d) ÷ Total MTYLD supply |
| `treasuryActiveUSDC()` | Contract balance minus pendingRevenueUSDC |
| `pendingRevenueUSDC` | USDC queued until release delay expires |
| `applyPendingRevenue()` | Moves pending to active, increasing NAV |

---

## 🧱 Fee Mechanics

| Type | Default | Max | Destination |
|------|----------|------|-------------|
| Mint Fee | 0 bps | 500 bps (5%) | `feeRecipient` |
| Redeem Fee | 0 bps | 500 bps (5%) | `feeRecipient` |

- **feeRoundUp** = true → conservative rounding (vault-friendly)  
- **feeRecipient** = `0x441468A2de612CDec993f69407E481D30Ca5E203`  
- Changeable via `setFees(mintFeeBps, redeemFeeBps, newRecipient, roundUp)`

👉 To keep fees inside the vault (auto-compounding NAV):

```solidity
setFees(mintFeeBps, redeemFeeBps, address(this), feeRoundUp);
```

👉 To direct fees to Treasury:

```solidity
setFees(mintFeeBps, redeemFeeBps, 0xcfe077e6f7554B1724546E02624a0832D1f4557a, feeRoundUp);
```

---

## 🧰 Admin Controls

| Function | Description |
|-----------|-------------|
| `setFees()` | Adjust fee rates and recipient |
| `setGuardedLaunch()` | Restrict minting to whitelisted users |
| `setWhitelist()` | Add/remove early minters |
| `setMaxSupply()` | Optional mint cap |
| `setNavDelay()` | Adjust delay for revenue release |
| `beginEpochClose()` / `endEpochClose()` | Pause mint/redeem during revenue sync |
| `whitelistRescuable()` / `announceRescue()` / `executeRescue()` | Time-locked rescue (non-stable assets only) |

---

## 🧾 Example Lifecycle

| Phase | Example |
|--------|---------|
| Mint | User deposits $1,000 USDC, fee 1% → 10 USDC sent to feeRecipient |
| Revenue | Mechanical Temp injects $2,000 USDC as pending revenue |
| Release | After 1 hour, `applyPendingRevenue()` adds it to treasury, raising NAV |
| Redeem | Holder redeems MTYLD for $1,050 USDC, fee 1% → 10.5 USDC sent to feeRecipient |

---

## 🧠 Summary

- **Fees → feeRecipient** (currently treasury wallet).  
- **Pending Revenue → NAV Boost** (after delay).  
- **Redeem / Mint** fully transparent on-chain.  
- **NAV = USDC backing ÷ MTYLD supply.**

MTYLD turns *real HVAC revenue* into transparent, on-chain yield.

---

© 2025 **Mechanical Temp LLC** · Southfield, MI  
Vault Contract: `0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880`  
Stablecoin: `USDC` (`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`)
