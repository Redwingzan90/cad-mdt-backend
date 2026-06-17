import { Request, Response, NextFunction } from "express";
import { logger } from "../utils/logger";
import { Prisma } from "@prisma/client";

export interface AppError extends Error {
  statusCode?: number;
  code?: string;
  details?: unknown;
}

export function errorHandler(
  err: AppError,
  _req: Request,
  res: Response,
  _next: NextFunction
) {
  logger.error("Unhandled error:", {
    message: err.message,
    stack: err.stack,
    code: err.code,
    path: _req.path,
    method: _req.method,
  });

  // Prisma errors
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    switch (err.code) {
      case "P2002":
        return res.status(409).json({
          error: "A record with this value already exists.",
          field: (err.meta?.target as string[])?.join(", "),
        });
      case "P2025":
        return res.status(404).json({
          error: "Record not found.",
        });
      case "P2003":
        return res.status(400).json({
          error: "Referenced record does not exist.",
        });
      default:
        return res.status(400).json({
          error: "Database error occurred.",
          code: err.code,
        });
    }
  }

  if (err instanceof Prisma.PrismaClientValidationError) {
    return res.status(400).json({
      error: "Invalid data provided.",
    });
  }

  // Custom app errors
  if (err.statusCode) {
    return res.status(err.statusCode).json({
      error: err.message,
      code: err.code,
      details: err.details,
    });
  }

  // JWT errors
  if (err.name === "JsonWebTokenError") {
    return res.status(401).json({ error: "Invalid token." });
  }
  if (err.name === "TokenExpiredError") {
    return res.status(401).json({ error: "Token expired." });
  }

  // Default 500
  return res.status(500).json({
    error:
      process.env.NODE_ENV === "production"
        ? "Internal server error."
        : err.message,
  });
}

/**
 * Create a custom application error
 */
export function createError(
  statusCode: number,
  message: string,
  code?: string,
  details?: unknown
): AppError {
  const error: AppError = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  error.details = details;
  return error;
}
