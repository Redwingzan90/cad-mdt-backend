import { Router, Request, Response, NextFunction } from "express";

type RouteHandler = (req: Request, res: Response, next: NextFunction) => Promise<void>;

/**
 * Wrap async route handlers to catch errors
 */
export function asyncHandler(fn: RouteHandler) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

export const router = Router();
