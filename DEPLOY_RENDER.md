# Deploy CAD/MDT to Render (Free)

This uses Render's **free PostgreSQL database** — no TiDB or external database needed.

## Step 1: Push Your Code to GitHub

```bash
cd cad-system/backend
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/cad-mdt-backend.git
git push -u origin main
```

## Step 2: Deploy to Render

1. Go to [render.com](https://render.com) and sign up (no credit card needed)
2. Click **New +** → **Blueprint** (this uses the `render.yaml` file)
3. Connect your GitHub repo
4. Render will auto-detect the `render.yaml` and create both:
   - **cad-mdt-api** (Node.js web service)
   - **cad-mdt-db** (Free PostgreSQL database)
5. Click **Apply** and wait for deployment (~3-5 minutes)

**OR** manually:
1. Click **New +** → **Web Service**
2. Connect your GitHub repo
3. Fill in:
   - **Name:** `cad-mdt-api`
   - **Runtime:** Node
   - **Build Command:** `npm install && npx prisma generate && npm run build`
   - **Start Command:** `node dist/index.js`
4. Also create a **New +** → **PostgreSQL** database:
   - **Name:** `cad-mdt-db`
   - **Plan:** Free
5. Link the database to your web service via the `DATABASE_URL` env var

## Step 3: Run Database Migration

Once deployed, go to your web service's **Shell** tab in Render and run:
```bash
npx prisma migrate deploy
npx prisma db seed
```

## Step 4: Update FiveM Config

Your Render URL will be something like `https://cad-mdt-api.onrender.com`. Update your FiveM config:

```lua
Config.API = {
    URL = "https://cad-mdt-api.onrender.com",
    ServerKey = "cfxk_1kRjwnUDp7fMl0AGeWZHe_1U24R2",
    Timeout = 15000,  -- Increase timeout for free tier cold starts
}
```

## Important Notes

- **Free tier sleeps after 15 min** of inactivity — first request takes ~50 sec to wake up
- **750 free hours/month** — enough for testing
- **PostgreSQL database is free** and persistent (unlike MySQL on TiDB)
- **Updates:** Push to GitHub and Render auto-redeploys
- **No credit card needed** for the free tier
