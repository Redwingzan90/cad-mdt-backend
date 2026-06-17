import { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";
import { prisma } from "../index";
import { createError } from "./errorHandler";
import { securityLogger } from "../utils/logger";
import { resolveUserPermissions } from "../utils/helpers";

export interface AuthUser {
  id: string;
  username: string;
  officerId?: string;
  permissions: string[];
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

/**
 * Main authentication middleware
 * Validates JWT token and attaches user to request
 */
export async function authMiddleware(
  req: Request,
  _res: Response,
  next: NextFunction
) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      throw createError(401, "Authentication required.");
    }

    const token = authHeader.slice(7);
    const secret = process.env.JWT_SECRET;
    if (!secret) {
      throw createError(500, "JWT secret not configured.");
    }

    const decoded = jwt.verify(token, secret) as { id: string; username: string };

    // Fetch user with permissions and officer role
    const user = await prisma.user.findUnique({
      where: { id: decoded.id },
      include: {
        permissions: {
          include: { permission: true },
        },
        officer: {
          select: {
            id: true,
            status: true,
            roleId: true,
          },
        },
      },
    });

    if (!user || !user.active) {
      throw createError(401, "User not found or inactive.");
    }

    // Check session validity
    const session = await prisma.session.findFirst({
      where: {
        userId: user.id,
        token: token,
        expiresAt: { gt: new Date() },
      },
    });

    if (!session) {
      throw createError(401, "Session expired or invalid.");
    }

    // Build permissions list — merge direct user permissions + role permissions
    const permissions = await resolveUserPermissions(user.id);

    req.user = {
      id: user.id,
      username: user.username,
      officerId: user.officer?.id,
      permissions,
    };

    next();
  } catch (error) {
    next(error);
  }
}

/**
 * Permission check middleware factory
 */
export function requirePermission(...permissions: string[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) {
      return next(createError(401, "Authentication required."));
    }

    const hasPermission = permissions.some((p) =>
      req.user!.permissions.includes(p)
    );

    if (!hasPermission) {
      securityLogger.warn("Permission denied", {
        userId: req.user.id,
        required: permissions,
        actual: req.user.permissions,
        path: req.path,
        method: req.method,
      });
      return next(createError(403, "Insufficient permissions."));
    }

    next();
  };
}

/**
 * Generate a JWT token
 */
export function generateToken(user: { id: string; username: string }): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error("JWT_SECRET not set");

  return jwt.sign(
    { id: user.id, username: user.username },
    secret,
    { expiresIn: process.env.JWT_EXPIRES_IN || "24h" } as jwt.SignOptions
  );
}

/**
 * Create a session in the database
 */
export async function createSession(userId: string, token: string): Promise<void> {
  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + 24);

  await prisma.session.create({
    data: {
      userId,
      token,
      expiresAt,
    },
  });
}
