import { Router, Request, Response } from "express";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import {
  generateToken,
  createSession,
} from "../middleware/auth";
import { createError } from "../middleware/errorHandler";
import { securityLogger } from "../utils/logger";
import { resolveUserPermissions } from "../utils/helpers";
import { z } from "zod";

const router = Router();

// ============================================================
// Validation Schemas
// ============================================================
const loginSchema = z.object({
  username: z.string().min(3).max(64),
  password: z.string().min(6).max(128),
});

const registerSchema = z.object({
  username: z.string().min(3).max(64),
  password: z.string().min(8).max(128),
  email: z.string().email().optional(),
});

// ============================================================
// POST /api/auth/login
// ============================================================
router.post(
  "/login",
  asyncHandler(async (req: Request, res: Response) => {
    const body = loginSchema.parse(req.body);

    // Find user
    const user = await prisma.user.findUnique({
      where: { username: body.username },
      include: {
        officer: {
          include: {
            department: { select: { id: true, name: true, code: true } },
            rank: { select: { id: true, name: true, level: true } },
          },
        },
        permissions: {
          include: { permission: true },
        },
      },
    });

    if (!user || !user.active) {
      securityLogger.warn("Failed login attempt", {
        username: body.username,
        ip: req.ip,
        reason: "User not found or inactive",
      });
      throw createError(401, "Invalid username or password.");
    }

    // Verify password
    const validPassword = await bcrypt.compare(body.password, user.passwordHash);
    if (!validPassword) {
      securityLogger.warn("Failed login attempt", {
        username: body.username,
        ip: req.ip,
        reason: "Invalid password",
      });
      throw createError(401, "Invalid username or password.");
    }

    // Generate token
    const token = generateToken({ id: user.id, username: user.username });

    // Create session
    await createSession(user.id, token);

    // Build permissions — merge direct user permissions + role permissions
    const permissions = await resolveUserPermissions(user.id);

    // Audit log
    await prisma.auditLog.create({
      data: {
        userId: user.id,
        action: "LOGIN",
        resource: "auth",
        ipAddress: req.ip || "unknown",
      },
    });

    res.json({
      token,
      user: {
        id: user.id,
        username: user.username,
        permissions,
        officer: user.officer
          ? {
              id: user.officer.id,
              firstName: user.officer.firstName,
              lastName: user.officer.lastName,
              badgeNumber: user.officer.badgeNumber,
              department: user.officer.department,
              rank: user.officer.rank,
              callsign: user.officer.callsign,
              status: user.officer.status,
            }
          : null,
      },
    });
  })
);

// ============================================================
// POST /api/auth/logout
// ============================================================
router.post(
  "/logout",
  asyncHandler(async (req: Request, res: Response) => {
    const authHeader = req.headers.authorization;
    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.slice(7);
      await prisma.session.deleteMany({ where: { token } });
    }

    res.json({ message: "Logged out successfully." });
  })
);

// ============================================================
// GET /api/auth/me
// ============================================================
router.get(
  "/me",
  asyncHandler(async (req: Request, res: Response) => {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      throw createError(401, "Authentication required.");
    }

    const token = authHeader.slice(7);
    const secret = process.env.JWT_SECRET;
    if (!secret) throw createError(500, "JWT secret not configured.");

    const decoded = jwt.verify(token, secret) as { id: string };

    const user = await prisma.user.findUnique({
      where: { id: decoded.id },
      include: {
        officer: {
          include: {
            department: true,
            rank: true,
            certifications: true,
            role: { select: { id: true, name: true, level: true } },
          },
        },
        permissions: {
          include: { permission: true },
        },
      },
    });

    if (!user) throw createError(404, "User not found.");

    // Build permissions — merge direct user permissions + role permissions
    const permissions = await resolveUserPermissions(user.id);

    res.json({
      id: user.id,
      username: user.username,
      permissions,
      officer: user.officer || null,
    });
  })
);

// ============================================================
// POST /api/auth/register (Admin only - protected separately)
// ============================================================
router.post(
  "/register",
  asyncHandler(async (req: Request, res: Response) => {
    const body = registerSchema.parse(req.body);

    // Check if username exists
    const existing = await prisma.user.findUnique({
      where: { username: body.username },
    });
    if (existing) {
      throw createError(409, "Username already taken.");
    }

    // Hash password
    const passwordHash = await bcrypt.hash(body.password, 12);

    // Create user
    const user = await prisma.user.create({
      data: {
        username: body.username,
        passwordHash,
        email: body.email,
      },
    });

    res.status(201).json({
      message: "User created successfully.",
      user: { id: user.id, username: user.username },
    });
  })
);

export { router as authRoutes };
