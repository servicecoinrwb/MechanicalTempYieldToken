# ⚙️ YieldWorks Protocol  
### Powered by [Mechanical Temp HVAC](https://mechanicaltemp.com)

**YieldWorks** is a decentralized finance (**DeFi**) protocol built on **Arbitrum** that allows investors to earn yield backed by real-world HVAC projects completed by **Mechanical Temp**, a licensed service company based in Southfield, MI.

---

## 🌐 Overview

YieldWorks bridges traditional business operations with blockchain transparency.  
Instead of relying on bank loans, **Mechanical Temp** tokenizes a portion of its **future revenue** from completed HVAC jobs — raising working capital directly from **DeFi investors**.

The core token, **Mechanical Temp Yield (MTYLD)**, represents a fractional claim on **USDC reserves** held in the smart contract. These reserves grow as projects are completed and repaid, increasing the value of each token.

---

## 🔁 How It Works

### 1. Propose Mint
Mechanical Temp identifies a new HVAC project and proposes its tokenization through the smart contract.  
Includes project details such as **grossYield** and description.

### 2. Safety Delay
A waiting period (`PROPOSAL_DELAY`, typically 1 day) ensures transparency before any new token mints.

### 3. Execute Mint
After the delay:
- The contract mints **MTYLD** representing 10% of the project’s grossYield.  
- 5% of this is reserved as internal backing.  
- Tokens become available for investors to purchase.

### 4. Back with Capital (Investor Action)
Investors buy MTYLD using **USDC** through the [YieldWorks Dashboard](app.html), providing capital for ongoing projects.

### 5. Complete Work & Payout
Mechanical Temp completes the real-world HVAC job and receives off-chain payment.

### 6. Repay Protocol
The owner repays the **tokenizedValue** (in USDC) via `payoutWorkOrder()`.  
This increases the USDC reserves, effectively generating yield for holders.

### 7. Earn Yield
Since the protocol retains the **5% reserve**, every successful repayment increases the **backing per MTYLD** — producing organic yield.

### 8. Redeem Tokens
Investors can redeem MTYLD anytime to receive a proportional share of USDC, minus a **redemption fee (10%)**.

---

## 🔒 Key Features & Security Measures

- **Real-World Backing:** Operated by a public, licensed HVAC business.  
- **Full On-Chain Transparency:** All actions recorded on Arbitrum.  
- **Timelocked Admin Actions:** Mints and fee changes require proposals and waiting periods.  
- **Emergency Controls:** Owner can pause protocol functions during emergencies.  
- **Restricted Withdrawals:** Prevents arbitrary removal of USDC reserves.  
- **Slippage Protection:** User-defined minOut parameters in buy/redeem.  
- **SafeERC20 Integration:** Uses OpenZeppelin’s secure library for token transfers.

---

## 💰 Tokenomics (`$MTYLD`)

| Parameter | Description |
|------------|--------------|
| **Token Name** | Mechanical Temp Yield |
| **Symbol** | MTYLD |
| **Decimals** | 18 |
| **Network** | Arbitrum One |
| **Backing Token** | [USDC (0xaf88…5831)](https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831) |
| **Value Basis** | Total USDC / Total MTYLD Supply |
| **Tokenization Ratio** | 10% of each job’s grossYield |
| **Reserve Ratio** | 5% of tokenizedValue retained |
| **Yield Source** | Reserve accumulation from completed, repaid jobs |
| **Redemption Fee** | 10% (adjustable, up to 20%) |

---

## ⚠️ Risks & Considerations

### 🔸 Centralization Risk — **High**
The system depends on **Mechanical Temp’s honesty and performance**.  
The owner controls all key protocol actions and repayments are off-chain verified.

### 🔸 Economic Risks — **Medium**
- Price front-running during buy/redeem possible.  
- Yield depends on job completion and repayment success.  

### 🔸 Smart Contract Risk — **Low-Medium**
- Based on secure, standard libraries, but **not yet formally audited**.  
- USDC stability and contract functionality are external dependencies.

> **Investors must understand and accept these risks, especially the reliance on Mechanical Temp’s business integrity.**

---

## 🧭 How to Use (Investors)

1. **Connect Wallet:** Use MetaMask or another Arbitrum-compatible wallet.  
2. **Fund Wallet:** Hold native **Arbitrum USDC**.  
3. **Visit Dashboard:** Open [`app.html`](app.html).  
4. **Approve USDC:** Grant token approval before purchase.  
5. **Buy MTYLD:** Input desired USDC amount and execute the transaction.  
6. **Hold or Redeem:** Redeem anytime to withdraw proportional USDC.

---

## 🧱 Contract Information

| Type | Address | Description |
|------|----------|-------------|
| **Network** | Arbitrum One | — |
| **MTYLD Token Contract** | [`0xae2C05f01DBCC6C8AF40EbFA3339Af10dbECdFD0`](https://arbiscan.io/address/0xae2C05f01DBCC6C8AF40EbFA3339Af10dbECdFD0) | Main YieldWorks contract |
| **Payment Token (USDC)** | [`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`](https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831) | Arbitrum native USDC |

---

## 📘 Disclaimer

This document is for informational purposes only.  
**YieldWorks Protocol** involves real-world business dependencies and cryptocurrency risk.  
Always perform your own due diligence (DYOR) before investing.

---

### 🧰 Repository Structure (Recommended)

