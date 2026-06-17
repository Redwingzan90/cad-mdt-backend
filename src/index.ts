import "dotenv/config";
import express from "express";
import { createServer } from "http";
import { Server as SocketServer } from "socket.io";
import cors from "cors";
import helmet from "helmet";
import morgan from "morgan";
import rateLimit from "express-rate-limit";
import { PrismaClient } from "@prisma/client";

import { logger } from "./utils/logger";
import { errorHandler } from "./middleware/errorHandler";
import { authMiddleware } from "./middleware/auth";

// Route imports
import { authRoutes } from "./routes/auth";
import { officerRoutes } from "./routes/officers";
import { dispatchRoutes } from "./routes/dispatch";
import { emergencyRoutes } from "./routes/emergency";
import { civilianRoutes } from "./routes/civilians";
import { vehicleRoutes } from "./routes/vehicles";
import { criminalRoutes } from "./routes/criminal";
import { boloRoutes } from "./routes/bolos";
import { evidenceRoutes } from "./routes/evidence";
import { reportRoutes } from "./routes/reports";
import { notificationRoutes } from "./routes/notifications";
import { adminRoutes } from "./routes/admin";
import { dashboardRoutes } from "./routes/dashboard";
import { searchRoutes } from "./routes/search";
import { departmentRoutes } from "./routes/departments";

// Socket handler
import { initializeSocket } from "./socket";

// ============================================================
// Prisma Client (Singleton)
// ============================================================
export const prisma = new PrismaClient({
  log: process.env.NODE_ENV === "development" ? ["query", "error", "warn"] : ["error"],
});

// ============================================================
// Express App Setup
// ============================================================
const app = express();
const httpServer = createServer(app);

const PORT = parseInt(process.env.PORT || "3001", 10);
const HOST = process.env.HOST || "0.0.0.0";

// ============================================================
// Socket.io Setup
// ============================================================
const io = new SocketServer(httpServer, {
  cors: {
    origin: process.env.CORS_ORIGIN || "http://localhost:5173",
    methods: ["GET", "POST"],
    credentials: true,
  },
  pingTimeout: 60000,
  pingInterval: 25000,
});

export { io };

// ============================================================
// Middleware
// ============================================================

// Security headers
app.use(
  helmet({
    contentSecurityPolicy: false, // NUI needs flexible CSP
    crossOriginEmbedderPolicy: false,
  })
);

// CORS
app.use(
  cors({
    origin: process.env.CORS_ORIGIN || "http://localhost:5173",
    credentials: true,
  })
);

// Request logging
app.use(morgan("combined", {
  stream: { write: (message: string) => logger.info(message.trim()) },
}));

// Body parsing
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

// Rate limiting
const limiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || "900000", 10),
  max: parseInt(process.env.RATE_LIMIT_MAX || "100", 10),
  message: { error: "Too many requests, please try again later." },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use("/api/", limiter);

// Stricter rate limit for auth endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // 10 attempts
  message: { error: "Too many login attempts, please try again later." },
});
app.use("/api/auth/login", authLimiter);

// ============================================================
// Health Check (no auth required)
// ============================================================
app.get("/api/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// ============================================================
// API Routes
// ============================================================
app.use("/api/auth", authRoutes);
app.use("/api/dashboard", authMiddleware, dashboardRoutes);
app.use("/api/officers", authMiddleware, officerRoutes);
app.use("/api/dispatch", authMiddleware, dispatchRoutes);
app.use("/api/emergency", authMiddleware, emergencyRoutes);
app.use("/api/civilians", authMiddleware, civilianRoutes);
app.use("/api/vehicles", authMiddleware, vehicleRoutes);
app.use("/api/criminal", authMiddleware, criminalRoutes);
app.use("/api/bolos", authMiddleware, boloRoutes);
app.use("/api/evidence", authMiddleware, evidenceRoutes);
app.use("/api/reports", authMiddleware, reportRoutes);
app.use("/api/notifications", authMiddleware, notificationRoutes);
app.use("/api/admin", authMiddleware, adminRoutes);
app.use("/api/search", authMiddleware, searchRoutes);
app.use("/api/departments", authMiddleware, departmentRoutes);

// ============================================================
// FiveM Integration Routes (IP-restricted)
// ============================================================
import { fivemRoutes } from "./routes/fivem";
app.use("/api/fivem", fivemRoutes);

// ============================================================
// Error Handler (must be last)
// ============================================================
app.use(errorHandler);

// ============================================================
// Initialize Socket.io
// ============================================================
initializeSocket(io);

// ============================================================
// Start Server
// ============================================================
async function start() {
  try {
    // Test database connection
    await prisma.$connect();
    logger.info("Database connected successfully");

    httpServer.listen(PORT, HOST, () => {
      logger.info(`CAD/MDT API server running on http://${HOST}:${PORT}`);
      logger.info(`Environment: ${process.env.NODE_ENV || "development"}`);
    });
  } catch (error) {
    logger.error("Failed to start server:", error);
    process.exit(1);
  }
}

start();

// Graceful shutdown
process.on("SIGINT", async () => {
  logger.info("Shutting down gracefully...");
  await prisma.$disconnect();
  httpServer.close(() => {
    logger.info("Server closed");
    process.exit(0);
  });
});

process.on("SIGTERM", async () => {
  logger.info("SIGTERM received, shutting down...");
  await prisma.$disconnect();
  httpServer.close(() => {
    process.exit(0);
  });
});
