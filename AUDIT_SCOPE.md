# 🧾 MTYLD Credit Line — Audit Scope  
**Project:** Mechanical Temp (MTYLD)  
**Network:** Arbitrum One (chainId 42161)  
**Date:** October 2025  
**Contact:** Brian Estes — Mechanical Temp
**Email / Telegram:** @TR0UBL35H00T3R  

---

## 📦 Overview

The **MTYLD Credit Line** allows whitelisted users to borrow **USDC** against **MTYLD token collateral**.  
The system is operated by **Mechanical Temp**, a real HVAC company based in Southfield, MI, and uses an on-chain lending vault to bridge real-world revenue into a transparent DeFi structure.

The audit focuses on validating the correctness, security, and trust assumptions of the **LendingVaultGatedV3** smart contract and its interactions with the DAO treasury, vault price feed, and external ERC20 tokens.

---

## 🎯 Primary Goals

- Validate collateral deposit, withdrawal, borrow, and repay logic  
- Verify that interest, late fees, and liquidation calculations are accurate and safe  
- Confirm correct enforcement of LTV ratios, liquidation thresholds, and role-based permissions  
- Identify any reentrancy, over/underflow, or external call risks  
- Check access controls for `owner`, `rateGuardian`, and `riskGuardian` roles  
- Ensure treasury funding and approvals are securely handled via Gnosis Safe  
- Evaluate precision and rounding behavior (USDC 6 decimals vs USD 18 decimals)  
- Assess gas efficiency and overall contract design simplicity  

---

## 📂 Scope Files

### Solidity Contracts
| File | Description |
|------|--------------|
| `contracts/LendingVaultGatedV3.sol` | Primary contract implementing collateralized lending with whitelist gating, APR-based interest, and severe liquidation logic |
| `interfaces/IERC20.sol` | ERC20 interface |
| `interfaces/IMTYLDVault.sol` | Interface for price-per-token oracle |
| `libraries/SafeERC20.sol` | Safe token transfer helpers |
| `libraries/FullMath.sol` | Precision math used for interest and liquidation calculations |

> No proxy or upgrade pattern used. Single, non-upgradeable deployment.

### Frontend (for integration review)
| File | Description |
|------|--------------|
| `frontend/index.html` | Simple ethers.js + Tailwind UI for interaction |
| Embedded script | Reads and writes to `LendingVaultGatedV3` via MetaMask or Safe wallet |

---

## 🔗 Deployment Info

| Component | Address | Notes |
|------------|----------|-------|
| **LendingVaultGatedV3** | `0x1B563D1763CA148D8bb23B0e490E3570DEa5e4b7` | Main audited contract |
| **USDC (Arbitrum)** | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | Stablecoin used for borrowing |
| **Treasury (Gnosis Safe)** | `0x441468A2de612CDec993f69407E481D30Ca5E203` | DAO multisig providing liquidity and receiving repayments |
| **MTYLD Token** | `0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880` | ERC20 collateral token |
| **MTYLD Vault** | `0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880` | Price feed for USD value of MTYLD (via `pricePerToken()`) |

---

## 🧮 External Integrations

- **Ethers.js (v6.11.1)** for frontend contract calls  
- **TailwindCSS (CDN)** for UI styling  
- **Gnosis Safe** for treasury management and approvals  
- **Arbitrum RPC:** `https://arb1.arbitrum.io/rpc`  
- **Arbiscan** for public contract verification and read-only monitoring  

---

## ⚙️ Key Contract Parameters

| Parameter | Description | Units |
|------------|--------------|--------|
| `aprBps` | Annual percentage rate | Basis points |
| `maxLtvBps` | Max loan-to-value ratio | Basis points |
| `liqThresholdBps` | Liquidation threshold | Basis points |
| `liqBonusBps` | Liquidation bonus | Basis points |
| `lateFeeBpsFlat` | Flat late fee after maturity | Basis points |
| `severeLiqThresholdBps` | Threshold for severe liquidation | Basis points |
| `severeLiqBonusBps` | Bonus for severe liquidators | Basis points |

---

## 🛠️ Functions for Review

Core user functions:
- `depositCollateral(uint256 amountMTYLD_18)`
- `withdrawCollateral(uint256 amountMTYLD_18)`
- `borrow(uint256 usdcAmount_6, uint64 maturity)`
- `repay(uint256 usdcAmount_6)`
- `liquidate(address user, uint256 repayUSDC_6, uint256 minSeizeMTYLD_18)`
- `severeLiquidate(address user, uint256 minSeizeMTYLD_18)`

Admin functions:
- `setRoles(address treasury, address rateGuardian, address riskGuardian)`
- `setParams(uint16 aprBps, uint16 maxLtvBps, uint16 liqThresholdBps, uint16 liqBonusBps)`
- `setSevereParams(uint16 sevThresh, uint16 sevBonus, bool public)`
- `setWhitelist(address user, bool allowed)`
- `adminSetCredit(address user, uint32 score)`
- `pause()` / `unpause()`
- `setLiquidationPaused(bool on)`

---

## 🧱 In-Scope Contracts Behavior Summary

- Borrowing and repayment denominated in **USDC (6 decimals)**  
- Collateral and internal valuation in **USD 18 decimals**  
- Interest accrues linearly by APR × time since borrow  
- Late fees apply after `maturity` timestamp  
- Collateral value fetched from `pricePerToken()` in `MTYLD_VAULT`  
- Liquidation uses `FullMath.mulDiv` for precision; bonus applied via `liqBonusBps` or `severeLiqBonusBps`  
- All admin functions restricted to `onlyOwnerOrGuardian`  

---

## 🚫 Out of Scope

- Other contracts (e.g. staking vaults, reward distributors)  
- Off-chain interfaces or APIs  
- UI styling / frontend design  
- Future versions (V4 and beyond)  

---

## 🧩 References

- [Vault dApp](https://vault.mechanicaltemp.com/vault.html)
- [Arbiscan link for MechanicalTempYield (MTYLD)](https://arbiscan.io/address/0xed33364f71275e8ea06a85a363ec5c5a6c9ab880)  
- [Arbiscan link for LendingVaultGatedV3](https://arbiscan.io/address/0x1B563D1763CA148D8bb23B0e490E3570DEa5e4b7)  
- [USDC (Arbitrum)](https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831)  
- [Mechanical Temp](https://mechanicaltemp.com)

---
