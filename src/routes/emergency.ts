import { Router, Request, Response } from "express";
import { prisma, io } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString, parsePagination, paginatedResponse } from "../utils/helpers";
import { requirePermission } from "../middleware/auth";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/emergency - List emergency calls
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const status = req.query.status as string | undefined;

    const where: any = {};
    if (status) where.status = status;

    const [calls, total] = await Promise.all([
      prisma.emergencyCall.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
      }),
      prisma.emergencyCall.count({ where }),
    ]);

    res.json(paginatedResponse(calls, total, page, limit));
  })
);

// ============================================================
// POST /api/emergency - Submit 911 call
// ============================================================
const createEmergencySchema = z.object({
  callerName: z.string().min(1).max(128),
  callerPhone: z.string().max(20).optional(),
  description: z.string().min(1).max(5000),
  location: z.string().min(1).max(255),
  lat: z.number().optional(),
  lng: z.number().optional(),
  type: z.string().min(1).max(64),
});

router.post(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createEmergencySchema.parse(req.body);

    const call = await prisma.emergencyCall.create({
      data: {
        callerName: sanitizeString(body.callerName),
        callerPhone: body.callerPhone,
        description: sanitizeString(body.description),
        location: sanitizeString(body.location),
        lat: body.lat,
        lng: body.lng,
        type: sanitizeString(body.type),
        status: "PENDING",
      },
    });

    // Broadcast to dispatch
    io.to("dispatch").emit("emergency:new", call);
    io.to("notifications").emit("notification:new", {
      type: "NEW_CALL",
      title: "911 Emergency Call",
      message: `${body.type}: ${body.description.slice(0, 100)}`,
      priority: "URGENT",
      data: call,
    });

    res.status(201).json(call);
  })
);

// ============================================================
// PATCH /api/emergency/:id - Update emergency call
// ============================================================
router.patch(
  "/:id",
  requirePermission("dispatch", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const { status, linkedCallId } = req.body;

    const call = await prisma.emergencyCall.update({
      where: { id: req.params.id },
      data: {
        ...(status && { status }),
        ...(linkedCallId && { linkedCallId }),
      },
    });

    io.to("dispatch").emit("emergency:update", call);

    res.json(call);
  })
);

export { router as emergencyRoutes };
