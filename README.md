# Police CAD/MDT System

A professional-grade Computer Aided Dispatch (CAD) and Mobile Data Terminal (MDT) system for FiveM roleplay servers.

## Features

- **Real-time Dispatch** — Live call management with priority levels, unit assignment, and status tracking
- **911 Emergency Calls** — Players can submit emergency calls with location and description
- **Officer Management** — On/off duty, status tracking, callsign assignment, unit management
- **Civilian Database** — Character profiles, licenses, criminal history, warrants
- **Vehicle Database** — Plate lookup, registration, insurance, stolen vehicle flags
- **Criminal Records** — Arrest reports, citations, warnings, warrants
- **BOLO System** — Person, vehicle, and officer safety alerts
- **Evidence Management** — Track evidence linked to cases
- **Report System** — Incident, crash, use of force, and investigation reports with supervisor approval
- **Live Map** — Real-time officer positions and call locations
- **Admin Panel** — User, department, rank, and permission management
- **Audit Logging** — Full activity and security audit trail
- **FiveM Integration** — Supports QBCore, ESX, Qbox, and standalone servers

## Tech Stack

| Component | Technology |
|-----------|------------|
| Frontend | Vue 3 + TypeScript + Tailwind CSS |
| Backend | Node.js + Express + Socket.io |
| Database | MySQL + Prisma ORM |
| Real-time | Socket.io (WebSockets) |
| FiveM | Lua client/server scripts |

## Project Structure

```
cad-system/
├── backend/              # Node.js API server
│   ├── src/
│   │   ├── index.ts      # Main entry point
│   │   ├── socket.ts     # Socket.io handler
│   │   ├── middleware/    # Auth, error handling
│   │   ├── routes/       # API routes (14 modules)
│   │   └── utils/        # Logger, helpers
│   └── prisma/
│       └── seed.ts       # Database seed data
├── web-ui/               # Vue 3 frontend (NUI overlay)
│   ├── src/
│   │   ├── views/        # 10 page views
│   │   ├── components/   # Reusable components
│   │   ├── stores/       # Pinia state management
│   │   ├── api/          # HTTP + Socket clients
│   │   └── router/       # Vue Router config
│   └── vite.config.ts
├── fivem-resource/       # FiveM Lua resource
│   ├── fxmanifest.lua    # Resource manifest
│   ├── config.lua        # Configuration
│   ├── client.lua        # Client-side scripts
│   ├── server.lua        # Server-side scripts
│   └── exports.lua       # Export documentation
├── database/
│   ├── schema.prisma     # Complete database schema
│   └── migrations/       # SQL migrations
└── README.md             # This file
```

## Prerequisites

- **Node.js** 18+ and npm/pnpm
- **MySQL** 8.0+ or MariaDB 10.6+
- **FiveM Server** (txAdmin or standalone)
- **Git** (optional)

## Installation

### 1. Database Setup

Create a MySQL database:

```sql
CREATE DATABASE cad_mdt CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 2. Backend Setup

```bash
cd backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env
# Edit .env with your database credentials and JWT secret

# Push database schema
npx prisma db push

# Seed default data (departments, ranks, admin user)
npx tsx prisma/seed.ts

# Start development server
npm run dev
```

The API server will start on `http://localhost:3001`.

### 3. Frontend Setup

```bash
cd web-ui

# Install dependencies
npm install

# Start development server
npm run dev
```

The frontend will be available at `http://localhost:5173`.

### 4. Build for Production

```bash
cd web-ui
npm run build
```

Copy the `web-ui/dist/` folder to `fivem-resource/web/` for NUI integration.

### 5. FiveM Resource Setup

1. Copy the `fivem-resource/` folder to your FiveM server's `resources/` directory
2. Rename it to `cad-mdt/`
3. Edit `config.lua` with your settings:
   - Set `Config.API.URL` to your backend API URL
   - Set `Config.API.ServerKey` to match your backend's `FIVEM_SERVER_KEY`
   - Configure framework detection
   - Set keybinds and features
4. Add `ensure cad-mdt` to your `server.cfg`

### 6. Create Admin User

Default admin credentials (created by seed):
- **Username:** `admin`
- **Password:** `admin123`

**⚠️ Change the password immediately in production!**

## Configuration

### Backend (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | MySQL connection string | — |
| `PORT` | API server port | `3001` |
| `JWT_SECRET` | JWT signing secret | — |
| `JWT_EXPIRES_IN` | Token expiration | `24h` |
| `CORS_ORIGIN` | Allowed CORS origin | `http://localhost:5173` |
| `FIVEM_SERVER_KEY` | FiveM server auth key | — |
| `LOG_LEVEL` | Logging level | `info` |

### FiveM (config.lua)

| Setting | Description | Default |
|---------|-------------|---------|
| `Config.API.URL` | Backend API URL | `http://localhost:3001` |
| `Config.API.ServerKey` | Server authentication key | — |
| `Config.Framework` | Framework type | `auto` |
| `Config.NUI.Keybind` | MDT open/close key | `f7` |
| `Config.Emergency.Command` | 911 command | `911` |
| `Config.PlateCheck.Command` | Plate check command | `plate` |

## API Endpoints

### Authentication
- `POST /api/auth/login` — Login
- `POST /api/auth/logout` — Logout
- `GET /api/auth/me` — Current user info
- `POST /api/auth/register` — Register user

### Dashboard
- `GET /api/dashboard` — Full dashboard data

### Officers
- `GET /api/officers` — List officers
- `GET /api/officers/on-duty` — On-duty officers
- `POST /api/officers/:id/go-on-duty` — Go on duty
- `POST /api/officers/:id/go-off-duty` — Go off duty
- `PATCH /api/officers/:id/status` — Update status

### Dispatch
- `GET /api/dispatch/calls` — List calls
- `GET /api/dispatch/calls/active` — Active calls
- `POST /api/dispatch/calls` — Create call
- `PATCH /api/dispatch/calls/:id` — Update call
- `POST /api/dispatch/calls/:id/assign` — Assign officer
- `POST /api/dispatch/calls/:id/notes` — Add note

### 911 / Emergency
- `GET /api/emergency` — List emergency calls
- `POST /api/emergency` — Submit 911 call

### Civilians
- `GET /api/civilians` — Search civilians
- `GET /api/civilians/:id` — Civilian profile
- `POST /api/civilians` — Create civilian

### Vehicles
- `GET /api/vehicles` — Search vehicles
- `GET /api/vehicles/plate/:plate` — Plate lookup

### Criminal Records
- `GET /api/criminal/arrests` — Arrest records
- `GET /api/criminal/citations` — Citations
- `GET /api/criminal/warnings` — Warnings
- `GET /api/criminal/warrants` — Warrants

### BOLOs
- `GET /api/bolos/active` — Active BOLOs
- `POST /api/bolos` — Create BOLO

### Reports
- `GET /api/reports/incidents` — Incident reports
- `GET /api/reports/crashes` — Crash reports
- `GET /api/reports/use-of-force` — Use of force reports
- `GET /api/reports/investigations` — Investigation reports

### Evidence
- `GET /api/evidence` — List evidence
- `POST /api/evidence` — Add evidence

### Admin
- `GET /api/admin/users` — Manage users
- `GET /api/admin/departments` — Departments
- `GET /api/admin/ranks` — Ranks
- `GET /api/admin/logs` — Audit logs

### Search
- `GET /api/search?q=` — Global search

### FiveM Integration (Server-key protected)
- `POST /api/fivem/player-duty` — Duty toggle
- `POST /api/fivem/plate-check` — Plate lookup
- `POST /api/fivem/911` — Submit 911
- `POST /api/fivem/location` — Update location

## Permissions System

| Permission | Description |
|------------|-------------|
| `admin` | Full system administration |
| `dispatch` | Dispatch operations |
| `manage_officers` | Manage officer profiles |
| `supervisor` | Supervisor functions |
| `view_reports` | View reports |
| `create_reports` | Create reports |
| `approve_reports` | Approve reports |
| `manage_evidence` | Manage evidence |
| `manage_bolos` | Create/manage BOLOs |
| `view_civilian_db` | View civilian database |
| `edit_civilian_db` | Edit civilian records |
| `view_vehicle_db` | View vehicle database |
| `edit_vehicle_db` | Edit vehicle records |
| `view_criminal_records` | View criminal records |
| `create_criminal_records` | Create criminal records |

## Default Accounts

| Username | Password | Role |
|----------|----------|------|
| `admin` | `admin123` | Administrator |
| `dispatcher` | `dispatch123` | Dispatcher |

**Change these passwords before production use!**

## Performance

- Designed to support **300+ concurrent players**
- Database queries use proper indexes
- Socket.io for real-time updates (no polling)
- Frontend uses lazy-loaded routes and virtual scrolling
- Rate limiting on all API endpoints
- Connection pooling via Prisma

## Security

- JWT-based authentication with session management
- Server-side validation on all endpoints (Zod schemas)
- Permission-based access control
- Rate limiting (100 req/15min general, 10 req/15min auth)
- Input sanitization on all user data
- SQL injection protection via Prisma ORM
- Audit logging for all actions
- FiveM server-key authentication for game integration
- Helmet security headers

## License

MIT License
