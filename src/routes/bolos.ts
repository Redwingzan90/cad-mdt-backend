import { Router, Request, Response } from "express";
import { prisma, io } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString, parsePagination, paginatedResponse, optionalDateTimeField } from "../utils/helpers";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/bolos - List BOLOs
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const type = req.query.type as string | undefined;
    const active = req.query.active as string | undefined;

    const where: any = {};
    if (type) where.type = type;
    if (active === "true") where.active = true;

    const [bolos, total] = await Promise.all([
      prisma.bolo.findMany({
        where,
        include: {
          creator: {
            select: { id: true, firstName: true, lastName: true, callsign: true },
          },
          targetCiv: {
            select: { id: true, firstName: true, lastName: true, dateOfBirth: true },
          },
          targetVehicle: {
            select: { id: true, plate: true, model: true, color: true },
          },
        },
        skip,
        take: limit,
        orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
      }),
      prisma.bolo.count({ where }),
    ]);

    res.json(paginatedResponse(bolos, total, page, limit));
  })
);

// ============================================================
// GET /api/bolos/active - Active BOLOs only
// ============================================================
router.get(
  "/active",
  asyncHandler(async (_req: Request, res: Response) => {
    const bolos = await prisma.bolo.findMany({
      where: {
        active: true,
        OR: [
          { expiresAt: null },
          { expiresAt: { gt: new Date() } },
        ],
      },
      include: {
        creator: {
          select: { firstName: true, lastName: true, callsign: true },
        },
        targetCiv: {
          select: { firstName: true, lastName: true, dateOfBirth: true },
        },
        targetVehicle: {
          select: { plate: true, model: true, color: true },
        },
      },
      orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
    });

    res.json(bolos);
  })
);

// ============================================================
// POST /api/bolos - Create BOLO
// ============================================================
const createBoloSchema = z.object({
  type: z.enum(["PERSON", "VEHICLE", "OFFICER_SAFETY"]),
  priority: z.enum(["LOW", "MEDIUM", "HIGH", "CRITICAL"]).default("MEDIUM"),
  description: z.string().min(1).max(5000),
  lastKnownLocation: z.string().max(255).optional(),
  targetCivId: z.string().uuid().optional(),
  targetVehicleId: z.string().uuid().optional(),
  expiresAt: optionalDateTimeField,
});

router.post(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createBoloSchema.parse(req.body);

    const bolo = await prisma.bolo.create({
      data: {
        type: body.type as any,
        priority: body.priority as any,
        description: sanitizeString(body.description),
        lastKnownLocation: body.lastKnownLocation
          ? sanitizeString(body.lastKnownLocation)
          : null,
        creatorId: req.user!.officerId!,
        targetCivId: body.targetCivId || null,
        targetVehicleId: body.targetVehicleId || null,
        expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
      },
      include: {
        creator: {
          select: { firstName: true, lastName: true, callsign: true },
        },
      },
    });

    // Broadcast BOLO
    io.to("dispatch").emit("bolo:new", bolo);
    io.to("notifications").emit("notification:new", {
      type: "BOLO_ALERT",
      title: `New ${body.type} BOLO`,
      message: body.description.slice(0, 200),
      priority: body.priority === "CRITICAL" ? "URGENT" : "HIGH",
      data: bolo,
    });

    res.status(201).json(bolo);
  })
);

// ============================================================
// PATCH /api/bolos/:id - Update BOLO
// ============================================================
router.patch(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const body = req.body;

    const bolo = await prisma.bolo.update({
      where: { id: req.params.id },
      data: {
        ...(body.description && { description: sanitizeString(body.description) }),
        ...(body.priority && { priority: body.priority }),
        ...(body.lastKnownLocation !== undefined && {
          lastKnownLocation: body.lastKnownLocation
            ? sanitizeString(body.lastKnownLocation)
            : null,
        }),
        ...(body.active !== undefined && { active: body.active }),
      },
    });

    io.to("dispatch").emit("bolo:update", bolo);

    res.json(bolo);
  })
);

// ============================================================
// DELETE /api/bolos/:id - Deactivate BOLO
// ============================================================
router.delete(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.bolo.update({
      where: { id: req.params.id },
      data: { active: false },
    });

    io.to("dispatch").emit("bolo:removed", { id: req.params.id });

    res.json({ message: "BOLO deactivated." });
  })
);

export { router as boloRoutes };
