# 🧰 MTYLD Vault dApp (Mechanical Temp Yield)

**MTYLD (Mechanical Temp Yield)** is a decentralized revenue-backed vault built on **Arbitrum**.  
It tokenizes real HVAC business income from **Mechanical Temp LLC** into an on-chain yield system.  
The more verified business revenue the DAO injects, the higher the token’s value (NAV).

This lightweight HTML dApp lets users **mint / redeem MTYLD tokens** and lets the owner manage the vault directly on-chain — without extra infrastructure.

---

## ⚙️ Features

- 🧮 **Live NAV display** — updates as new revenue is applied  
- 💰 **Mint / Redeem flow** — convert between USDC and MTYLD tokens  
- ⏳ **Revenue Queue System** — real job profits are added as “pending” until released  
- 🛠️ **Owner Panel** with:
  - Queue & apply revenue  
  - Set fees & recipient  
  - Toggle rounding mode  
  - Change NAV delay  
  - Guarded-launch whitelist  
  - Epoch open/close controls  

Everything runs through a single HTML + Ethers.js file — no backend or build step required.

---

## 🔗 Live Contract (Arbitrum)

| Item | Address |
|------|----------|
| **Vault** | [`0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880`](https://arbiscan.io/address/0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880) |
| **USDC** | [`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`](https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831) |

---

## 🪙 How the Vault Works

### 1. **Mint**
Users deposit **USDC** → the contract mints MTYLD tokens based on current price (NAV).

### 2. **Revenue Injection**
Mechanical Temp (the owner wallet) calls `injectRevenue(usdcAmount)`  
→ this transfers real business profits into the vault  
→ creates **pendingRevenueUSDC** locked for `navDelaySec` (default 3600 s)

### 3. **Revenue Application**
After the delay expires, anyone calls `applyPendingRevenue()`  
→ moves pending funds into the active treasury  
→ **increases NAV** (token value per MTYLD)

### 4. **Redeem**
Holders can redeem MTYLD for USDC at current NAV, minus any redeem fee.

This process ties the token’s appreciation directly to **verified HVAC job profits**, not speculation or trading fees.

---

## 🧑‍💻 Using the dApp

### 🧩 Connect & View
1. Open `index.html` in your browser.  
2. Click **Connect Wallet** (MetaMask → Arbitrum network).  
3. Dashboard shows:
   - Price per token (NAV)  
   - Active Treasury (USDC)  
   - Pending Revenue  
   - Countdown until next apply  

### 💵 For Regular Users
1. **Mint**
   - Enter amount of USDC → click *Preview* → *Mint*  
   - Confirm MetaMask approval if prompted  

2. **Redeem**
   - Enter MTYLD amount → click *Preview* → *Redeem*  

Slippage field protects you from NAV changes between transaction and confirmation.

---

## 🧑‍🔧 For Owner (Mechanical Temp DAO)

1. **Queue Revenue**
   - Enter USDC amount → click *Approve & Queue*  
   - USDC moves into contract as pendingRevenue  

2. **Apply Pending**
   - After delay, click *Apply Pending*  
   - Funds move into active treasury, raising NAV  

3. **Epoch Control**
   - *Begin Epoch Close* → temporarily pause mint/redeem  
   - *End Epoch Close* → reopen after applying revenue  

4. **Fee Settings**
   - Set mint/redeem fee in bps (100 bps = 1%)  
   - Choose recipient wallet  
   - Optionally round fees upward for exact USDC precision  

5. **Guarded Launch**
   - Enable to restrict minting to whitelisted wallets  
   - Add/remove whitelisted addresses  

6. **NAV Delay**
   - Adjust time (in seconds) before pending revenue can be applied  

---

## 🧠 Design Notes

- Uses **Safe math** and **reentrancy guards** in Solidity  
- NAV precision: 1e18 (18 decimals)  
- Treasury accounting: all values in 6-decimals USDC units  
- Anti-front-run: revenue is delayed (NAV locked until apply)  
- Protocol fee: configurable by owner (optional)  
- Read-only functions available for analytics dashboards (`pricePerToken`, `treasuryActiveUSDC`, `pendingRevenueUSDC`, etc.)

---

## 🧩 Tech Stack

- **Frontend:** pure HTML + CSS + [Ethers.js v6](https://docs.ethers.org/v6/)
- **Blockchain:** Arbitrum One  
- **Token Standard:** ERC-20 compatible vault token (MTYLD)  
- **Stablecoin:** USDC (6 decimals)  

No framework, no build tools — drop `index.html` anywhere (GitHub Pages, Netlify, Vercel).

---

## 🚀 Quick Deploy (GitHub Pages)

1. Create a new GitHub repo  
2. Upload your `index.html`  
3. In repo settings → *Pages* → set branch to `main` and root folder `/`  
4. Visit `https://<your-username>.github.io/<repo-name>/`

---

## 🧾 License

MIT License © 2025 Mechanical Temp LLC  

Use at your own risk. Smart contracts are immutable once deployed.  
Always test with small amounts before production usage.

---

### 💬 Questions / Support

For community & documentation, visit:

- 🌐 [mechanicaltemp.com](https://mechanicaltemp.com)  
- 💧 [service.money](https://service.money)  
- 🧱 [Service Coin DAO GitHub](https://github.com/servicecoinrwb)
