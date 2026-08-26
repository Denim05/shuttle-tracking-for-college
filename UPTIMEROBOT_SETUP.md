# ⚡ 100% Free Render Keep-Alive Configuration Guide

This guide ensures your **Render Free Web Service** (`https://smart-shuttle-backend-2h13.onrender.com`) stays **100% awake 24/7/365** with **zero cold-start delays** and **₹0 cost**.

---

## 🛡️ Dual-Layer Keep-Alive Architecture

Render spins down free web services after 15 minutes of inactivity. We have configured **3 fail-safe layers** to prevent sleep:

```
[Layer 1: Node.js Self-Ping] ──► Pings self every 10 min from inside server.js
[Layer 2: GitHub Actions]    ──► Pings https://smart-shuttle-backend-2h13.onrender.com every 10 min
[Layer 3: UptimeRobot (Free)]──► Pings URL every 5 minutes from external global servers
```

---

## 🚀 Step 3 (Optional 60-Second Setup): UptimeRobot External Pinger

To ensure 100% guaranteed 24/7 uptime even if the server restarts:

1. Open [https://uptimerobot.com](https://uptimerobot.com) and click **Register for FREE** (no credit card required).
2. Click **+ Add New Monitor**.
3. Fill in the following details:
   - **Monitor Type**: `HTTP(s)`
   - **Friendly Name**: `SISTecChalo Render Backend`
   - **URL (or IP)**: `https://smart-shuttle-backend-2h13.onrender.com/`
   - **Monitoring Interval**: `5 minutes`
4. Click **Create Monitor**.

---

## ✅ Verification
Once configured, UptimeRobot and GitHub Actions will ping your Render backend every 5–10 minutes, resetting Render's idle timer and ensuring **0 second delay** when drivers and students open the SISTecChalo app!
