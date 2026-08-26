# Google Cloud Deployment Guide for SISTecChalo

This guide details how to deploy the **SISTecChalo Express + Socket.io Backend** to **Google Cloud Run** and the **React Web Dashboard** to **Firebase Hosting**, keeping costs within Google Cloud's **100% Always Free Tier**.

---

## 🚀 Why Google Cloud instead of Render?

| Feature | Render Free Tier | Google Cloud (Cloud Run + Firebase) |
| :--- | :--- | :--- |
| **Cold Starts** | 50+ second delay after 15 min idle | **Sub-second startup** (or min-instances = 0/1) |
| **WebSockets** | Limited free connections | **Full native WebSocket & HTTP/2 support** |
| **Monthly Free Requests** | Strict execution caps | **2,000,000 requests/month FREE** |
| **Compute Free Allowance**| Spin-down inactivity mandatory | **360,000 GB-sec & 180,000 vCPU-sec FREE** |
| **SSL & CDN** | Custom setup | **Automatic global SSL & CDN** |

---

## 🛠️ Step 1: Deploy Backend to Google Cloud Run

### 1. Enable Required GCP Services
Run this command in terminal to enable Cloud Run and Artifact Registry for project `chalosistec`:

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com --project=chalosistec
```

### 2. Deploy Service to Cloud Run
From the repository root or `backend` folder, deploy directly from source using `gcloud run deploy`:

```bash
gcloud run deploy sistecchalo-backend \
  --source ./backend \
  --region asia-south1 \
  --allow-unauthenticated \
  --port 8080 \
  --set-env-vars="NODE_ENV=production,PORT=8080" \
  --project=chalosistec
```

*(Note: Replace `--region asia-south1` with `us-central1` or your preferred region).*

### 3. Configure Environment Variables in Cloud Run
Set your database and secret environment variables:

```bash
gcloud run services update sistecchalo-backend \
  --set-env-vars="MONGODB_URI=your_mongodb_atlas_uri,JWT_SECRET=your_jwt_secret,GOOGLE_MAPS_API_KEY=your_maps_api_key,SMTP_HOST=smtp.gmail.com,SMTP_PORT=587,SMTP_USER=your_email,SMTP_PASS=your_app_password" \
  --region asia-south1 \
  --project=chalosistec
```

Once deployment completes, `gcloud` will output your unique production URL, e.g.:
`https://sistecchalo-backend-xxxxxx-el.a.run.app`

---

## 🌐 Step 2: Deploy Web Dashboard to Firebase Hosting

### 1. Build Production Frontend Assets
```bash
cd web_dashboard
npm run build
cd ..
```

### 2. Deploy to Firebase Hosting
Deploy static assets to Firebase Hosting using project `chalosistec`:

```bash
firebase deploy --only hosting --project chalosistec
```

Your web dashboard will be live at:
`https://chalosistec.web.app` or `https://chalosistec.firebaseapp.com`

---

## 📱 Step 3: Update Flutter Mobile App Production URL

Open [`lib/constants/constants.dart`](file:///d:/BUS%20TRACKING/lib/constants/constants.dart) and replace `_productionUrl` with your Cloud Run service URL:

```dart
// Production Cloud Server URL (Google Cloud Run)
static const String _productionUrl = 'https://sistecchalo-backend-xxxxxx-el.a.run.app';
```

---

## 📊 Free Tier & Monitoring Tips

- **Cloud Run Costs**: Free tier covers 2,000,000 requests per month. If traffic is low, charges will be **$0.00**.
- **MongoDB Atlas**: Use the M0 cluster tier (512MB storage, shared RAM) which is 100% free forever.
- **Firebase Hosting**: Free tier includes 10 GB storage and 360 MB/day data transfer.
