# 🧾 MTYLD Ecosystem — Full Audit Scope

**Project:** Mechanical Temp (MTYLD Ecosystem)  
**Network:** Arbitrum One (chainId 42161)  
**Date:** October 2025  
**Contact:** Brian Estes — Mechanical Temp  
**Telegram:** [@TR0UBL35H00T3R](https://t.me/TR0UBL35H00T3R)  
**Website:** [(https://vault.mechanicaltemp.com/)](https://vault.mechanicaltemp.com/) 

---

## 📦 Overview

The **MTYLD Ecosystem** bridges real-world HVAC business revenue into decentralized finance via three core on-chain components:

1. **MTYLD Token** — the DAO’s primary revenue-backed asset.  
2. **MTYLD Vault** — NAV-based yield vault providing a live price feed (`pricePerToken()`), representing the treasury’s on-chain balance of USDC and RWA yield.  
3. **LendingVaultGatedV3** — a collateralized credit line that allows whitelisted users to borrow USDC against MTYLD collateral.

The ecosystem is designed for real-world businesses (Mechanical Temp) to tokenize earnings, provide on-chain transparency, and enable credit flow within the DAO framework.

---

## 🔗 Repository

**GitHub:** [https://github.com/servicecoinrwb/MechanicalTemp-MTYLD](https://github.com/servicecoinrwb/MechanicalTemp-MTYLD)  
**Branch:** `main`  
**Commit Hash:** `2853039`  

---

## 📂 Files in Scope

| File | Description |
|------|--------------|
| `contracts/MTYLDToken.sol` | ERC-20 token contract used as collateral and staking asset. |
| `contracts/MTYLDVault.sol` | NAV-based vault holding MTYLD and USDC; provides `pricePerToken()` feed. |
| `contracts/LendingVaultGatedV3.sol` | Core lending vault allowing whitelisted borrowing of USDC against MTYLD collateral. |
| `contracts/interfaces/IMTYLDVault.sol` | Interface for MTYLD Vault interactions. |
| `contracts/interfaces/IERC20.sol` | Minimal ERC-20 interface. |
| `contracts/flattened/LendingVaultGatedV3_Flattened.sol` | Verified flattened version for audit. |
| `frontend/index.html` | Frontend UI used for wallet connection, deposit, borrow, and repay testing. |

---

## 🧠 External Integrations

| Integration | Type | Description |
|--------------|------|--------------|
| **Arbitrum One** | Network | Layer-2 mainnet deployment. |
| **USDC** (`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`) | ERC-20 stablecoin used for lending and repayment. |
| **MetaMask / Ethers.js v6** | Wallet + JS library | Used in the frontend for user interaction. |
| **Gnosis Safe** | DAO Treasury | Multi-sig for owner and guardian roles. |

---

## 🧾 Deployment Addresses (Arbitrum Mainnet)

| Contract | Address | Description |
|-----------|----------|--------------|
| **LendingVaultGatedV3** | `0x1B563D1763CA148D8bb23B0e490E3570DEa5e4b7` | Credit line contract (core logic). |
| **MTYLD Vault** | `0xed33364f71275e8ea06a85a363ec5c5a6c9ab880` | Vault providing NAV-based MTYLD pricing feed. |
| **USDC** | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | Loan and repayment token. |
| **MTYLD Token** | *(add final ERC-20 address once confirmed)* | Collateral token (used by vault + lending system). |

---

## ⚙️ Role & Permission Structure

| Role | Description |
|------|--------------|
| **Owner (Treasury)** | DAO-controlled Gnosis Safe that can adjust key parameters. |
| **Rate Guardian** | Adjusts interest and LTV configuration parameters. |
| **Risk Guardian** | Oversees liquidation settings, pause controls, and severe-liq parameters. |
| **Whitelisted Borrowers** | Trusted entities (e.g., Mechanical Temp ops wallets). |
| **Vault Operator** | DAO multisig controlling deposits, USDC sweeps, and price updates in the MTYLD Vault. |

---

## 🧩 Components and Relationships

### 1️⃣ MTYLD Token  
- ERC-20 token representing a claim on Mechanical Temp DAO revenue.  
- Used as collateral in LendingVaultGatedV3.  
- May be staked or held in the MTYLD Vault for yield.  
- Security Focus:
  - Validate total supply, mint/burn permissions, and transfer restrictions.
  - Verify no hidden mint functions.
  - Confirm ownership is DAO-controlled.

### 2️⃣ MTYLD Vault  
- Accepts MTYLD deposits; holds USDC reserves.  
- Exposes `pricePerToken()` used for NAV-based collateral valuation.  
- Feeds live value to LendingVaultGatedV3.  
- Security Focus:
  - Validate NAV math and rounding safety.
  - Ensure no manipulation risk (e.g., deposits inflating NAV unfairly).
  - Confirm only trusted treasury can adjust balances.

### 3️⃣ LendingVaultGatedV3  
- Accepts MTYLD as collateral; lends USDC.  
- Calculates LTV based on MTYLD Vault’s price.  
- Enforces borrow caps, maturity, late fees, and liquidations.  
- Security Focus:
  - Reentrancy prevention.
  - Correct handling of decimals and math precision.
  - Price feed validation.
  - Access control on roles.

---

## 🚫 Out of Scope
- Off-chain Mechanical Temp HVAC operations or business processes.  
- Marketing or web assets (non-contract).  
- External stablecoin logic (USDC).  

---

## 🧱 Security Model

| Feature | Detail |
|----------|--------|
| **Non-upgradeable** | All contracts are immutable once deployed. |
| **Whitelisted Lending** | Borrowing is restricted to approved DAO participants. |
| **DAO Governance** | Parameter changes (APR, LTV, etc.) controlled via multi-sig. |
| **On-chain Valuation** | NAV from Vault determines collateral value (no off-chain oracles). |
| **No Flash Loans** | No dependency on manipulable DEX oracles. |
| **Emergency Controls** | Pausing and severe liquidation restricted to guardians. |

---

## 🛡️ Known Considerations
- **Oracle Trust:** Vault’s NAV logic should be reviewed for manipulation resistance.  
- **Math Precision:** Collateral/debt conversions use 18↔6 decimals — must be reviewed for rounding safety.  
- **Centralization Risk:** Guardian and treasury roles must remain DAO-controlled.  
- **Collateral Locking:** Verify withdraw safety under high-debt scenarios.  
- **Late Fee Logic:** Flat penalty per maturity miss; ensure consistent application.  

---

## 🔍 Auditor Guidance
Auditors should:
- Confirm **role-based permissions** cannot drain vault funds.  
- Simulate **collateral value manipulation** scenarios.  
- Test **full lifecycle:** deposit → borrow → accrue → repay → withdraw.  
- Review **Vault price integrity** under changing USDC balances.  
- Verify **cross-contract calls** (`pricePerToken()` reads) cannot be spoofed.  

---

## ✅ Summary

| Component | Purpose | Risk Level |
|------------|----------|-------------|
| **MTYLD Token** | ERC-20 collateral token | Low |
| **MTYLD Vault** | NAV-based yield vault (price feed) | Medium |
| **LendingVaultGatedV3** | USDC lending/borrowing engine | High |
