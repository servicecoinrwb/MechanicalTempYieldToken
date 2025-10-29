# 🧰 MTYLD Vault dApp (Mechanical Temp Yield)

**MTYLD (Mechanical Temp Yield)** is a decentralized revenue-backed vault built on **Arbitrum**, powered by  
[**Mechanical Temp**](https://mechanicaltemp.com/) — a Michigan-based HVAC company integrating real-world service profits with on-chain yield.

This mini dApp allows users to **mint and redeem MTYLD tokens**, while the business owner can **queue and apply real revenue** to grow the vault’s value (NAV) — turning verified HVAC income into transparent blockchain yield.

---

## ⚙️ Features

- 🧮 **Live NAV display** — updates automatically as new revenue is applied  
- 💰 **Mint / Redeem flow** — convert between USDC and MTYLD  
- ⏳ **Revenue Queue System** — real business profits enter as pending, then activate after a delay  
- 🛠️ **Owner Panel**
  - Queue & apply revenue  
  - Adjust fees and recipient  
  - Toggle rounding (up/down)  
  - Set NAV delay  
  - Guarded-launch & whitelist control  
  - Begin / End Epoch close periods  

> ⚡️ Everything runs in a single HTML + Ethers.js file — no backend, no build tools, instant deploy.

---

## 🔗 Live Contracts (Arbitrum)

| Type | Address | Description |
|------|----------|-------------|
| **Vault (MTYLD)** | [`0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880`](https://arbiscan.io/address/0xed33364f71275E8EA06a85a363Ec5C5a6c9AB880) | Core yield vault |
| **Stablecoin (USDC)** | [`0xaf88d065e77c8cC2239327C5EDb3A432268e5831`](https://arbiscan.io/token/0xaf88d065e77c8cC2239327C5EDb3A432268e5831) | Backing asset (6 decimals) |

---

## 🪙 How the Vault Works

### 1. **Mint**
Users deposit **USDC** → vault mints MTYLD tokens based on current NAV (price per token).

### 2. **Queue Revenue**
Mechanical Temp (the owner) calls `injectRevenue(usdcAmount)` to deposit verified business profits.  
Funds move into `pendingRevenueUSDC` and lock for `navDelaySec` seconds (e.g., 1 hour).

### 3. **Apply Revenue**
After the delay, anyone can call `applyPendingRevenue()` —  
pending funds become active treasury → **NAV rises** (token value increases).

### 4. **Redeem**
Holders can redeem MTYLD back to USDC at the updated NAV, minus optional fees.

| Step | Active Treasury | Pending | Action |
|------|-----------------|----------|--------|
| Initial | 10,000 | 0 | — |
| Owner queues 3,000 | 10,000 | 3,000 | `injectRevenue(3000)` |
| Wait 1 hr | 10,000 | 3,000 | — |
| Apply pending | 13,000 | 0 | `applyPendingRevenue()` |
| NAV ↑ 30% | — | — | Price increases |

---

## 🧑‍💻 How to Use the dApp

### 🧩 Connect Wallet
1. Open `index.html` in your browser (MetaMask → Arbitrum One).  
2. Click **Connect Wallet**.  
3. Dashboard shows:
   - Current NAV (Price per MTYLD)  
   - Active Treasury (USDC)  
   - Pending Revenue  
   - Countdown to next apply  

---

### 💵 For Users
- **Mint MTYLD**  
  Enter amount of USDC → click *Preview* → *Mint*.  
  Approve spending if prompted.  

- **Redeem MTYLD**  
  Enter MTYLD amount → click *Preview* → *Redeem*.  
  Tokens convert back to USDC at current NAV.

---

### 🧑‍🔧 For Owner (Mechanical Temp / DAO)
Use the **Owner Panel** at the bottom of the dashboard:

| Action | Function |
|---------|-----------|
| **Queue Revenue** | `injectRevenue(amount)` — transfers USDC into pending state |
| **Apply Revenue** | `applyPendingRevenue()` — activates pending funds |
| **Begin / End Epoch Close** | Temporarily pauses mint/redeem during sensitive updates |
| **Set Fees** | Adjust mint/redeem fees (in bps), recipient address, rounding mode |
| **Guarded Launch** | Enable/disable restricted minting; whitelist specific wallets |
| **NAV Delay** | Set how long pending revenue must sit before activation |

---

## 🧠 Design & Security

- 🧩 **SafeMath & ReentrancyGuard** protection  
- 📊 **NAV precision:** 1e18 (18 decimals)  
- 💵 **USDC accounting:** 6 decimals  
- ⏱️ **Anti-front-run:** time-delayed NAV updates  
- 🧰 **Owner fee controls:** adjustable in real time  
- 🔒 **Guarded launch mode:** whitelist-only minting until public release  

---

## 🧩 Tech Stack

- **Frontend:** pure HTML + CSS + [Ethers.js v6](https://docs.ethers.org/v6/)  
- **Blockchain:** Arbitrum One  
- **Stablecoin:** USDC  
- **Token:** ERC-20 compatible MTYLD vault token  

No dependencies, no build tools — simply open or host the HTML file.

---

## 🚀 Deploy on GitHub Pages

1. Create a new repo (e.g. `MTYLD-dapp`)  
2. Upload your `index.html`  
3. Go to **Settings → Pages**  
4. Choose branch `main` and folder `/`  
5. Access at:  
   `https://<your-username>.github.io/MTYLD-dapp/`

---

## 🌐 Official Links

- 💻 **Website:** [https://mechanicaltemp.com/](https://mechanicaltemp.com/)  
- 🧱 **Service Coin DAO GitHub:** [https://github.com/servicecoinrwb](https://github.com/servicecoinrwb)  
- 🌍 **Docs & Brand Ecosystem:** *Coming soon on [https://vault.mechanicaltemp.com]([https://vault.mechanicaltemp.com) 

---

## 🧾 License

MIT License © 2025 Mechanical Temp LLC  

> This vault represents real-world HVAC revenue tokenization.  
> Use at your own risk, always test with small amounts before production use.

---

### 💬 Support

For help integrating or verifying, contact:  
**admin@mechanicaltemp.com** or open an issue in the repo.
