import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { requirePermission } from "../middleware/auth";
import { parsePagination, paginatedResponse, sanitizeString } from "../utils/helpers";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/officers - List all officers
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const departmentId = req.query.departmentId as string | undefined;
    const status = req.query.status as string | undefined;

    const where: any = { active: true };
    if (departmentId) where.departmentId = departmentId;
    if (status) where.status = status;

    const [officers, total] = await Promise.all([
      prisma.officer.findMany({
        where,
        include: {
          department: { select: { id: true, name: true, code: true, color: true } },
          rank: { select: { id: true, name: true, level: true } },
          unit: { select: { callsign: true, status: true, vehicle: true } },
        },
        skip,
        take: limit,
        orderBy: [{ rank: { level: "desc" } }, { lastName: "asc" }],
      }),
      prisma.officer.count({ where }),
    ]);

    res.json(paginatedResponse(officers, total, page, limit));
  })
);

// ============================================================
// GET /api/officers/on-duty - List on-duty officers
// ============================================================
router.get(
  "/on-duty",
  asyncHandler(async (_req: Request, res: Response) => {
    const officers = await prisma.officer.findMany({
      where: {
        active: true,
        status: { not: "OFF_DUTY" },
      },
      include: {
        department: { select: { id: true, name: true, code: true, color: true } },
        rank: { select: { id: true, name: true, level: true } },
        unit: true,
      },
      orderBy: [{ callsign: "asc" }],
    });

    res.json(officers);
  })
);

// ============================================================
// GET /api/officers/:id - Get officer profile
// ============================================================
router.get(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const officer = await prisma.officer.findUnique({
      where: { id: req.params.id },
      include: {
        department: true,
        rank: true,
        role: true,
        certifications: true,
        trainingRecords: { orderBy: { completedAt: "desc" }, take: 10 },
        notes: { orderBy: { createdAt: "desc" }, take: 20 },
        disciplinary: { orderBy: { issuedAt: "desc" }, take: 10 },
        equipment: { where: { returnedAt: null } },
        unit: true,
      },
    });

    if (!officer) throw createError(404, "Officer not found.");
    res.json(officer);
  })
);

// ============================================================
// POST /api/officers/:id/go-on-duty
// ============================================================
const onDutySchema = z.object({
  callsign: z.string().min(1).max(32),
  departmentId: z.string().uuid(),
  vehicle: z.string().max(64).optional(),
});

router.post(
  "/:id/go-on-duty",
  asyncHandler(async (req: Request, res: Response) => {
    const body = onDutySchema.parse(req.body);

    // Check if already on duty
    const existingUnit = await prisma.unit.findUnique({
      where: { officerId: req.params.id },
    });
    if (existingUnit && !existingUnit.offDutyAt) {
      throw createError(400, "Officer is already on duty.");
    }

    // Remove old unit record if exists
    if (existingUnit) {
      await prisma.unit.delete({ where: { id: existingUnit.id } });
    }

    // Update officer status
    const officer = await prisma.officer.update({
      where: { id: req.params.id },
      data: {
        status: "AVAILABLE",
        callsign: body.callsign,
        departmentId: body.departmentId,
      },
    });

    // Create unit
    const unit = await prisma.unit.create({
      data: {
        officerId: officer.id,
        callsign: body.callsign,
        departmentId: body.departmentId,
        vehicle: body.vehicle,
        status: "AVAILABLE",
      },
    });

    res.json({ officer, unit });
  })
);

// ============================================================
// POST /api/officers/:id/go-off-duty
// ============================================================
router.post(
  "/:id/go-off-duty",
  asyncHandler(async (req: Request, res: Response) => {
    // Update officer
    const officer = await prisma.officer.update({
      where: { id: req.params.id },
      data: { status: "OFF_DUTY" },
    });

    // End unit
    await prisma.unit.updateMany({
      where: { officerId: req.params.id, offDutyAt: null },
      data: { offDutyAt: new Date(), status: "OUT_OF_SERVICE" },
    });

    // Remove from any active calls
    await prisma.callAssignment.updateMany({
      where: {
        officerId: req.params.id,
        clearedAt: null,
      },
      data: { clearedAt: new Date() },
    });

    res.json({ message: "Off duty.", officer });
  })
);

// ============================================================
// PATCH /api/officers/:id/status
// ============================================================
const statusSchema = z.object({
  status: z.enum([
    "AVAILABLE", "BUSY", "EN_ROUTE", "ON_SCENE",
    "TRANSPORTING", "OUT_OF_SERVICE", "BREAK",
  ]),
  statusDetail: z.string().max(64).optional(),
});

router.patch(
  "/:id/status",
  asyncHandler(async (req: Request, res: Response) => {
    const body = statusSchema.parse(req.body);

    const officer = await prisma.officer.update({
      where: { id: req.params.id },
      data: {
        status: body.status as any,
        statusDetail: body.statusDetail,
      },
    });

    // Update unit status too
    await prisma.unit.updateMany({
      where: { officerId: req.params.id, offDutyAt: null },
      data: { status: body.status as any },
    });

    res.json(officer);
  })
);

// ============================================================
// POST /api/officers - Create officer (admin)
// ============================================================
const createOfficerSchema = z.object({
  userId: z.string().uuid(),
  firstName: z.string().min(1).max(64),
  lastName: z.string().min(1).max(64),
  badgeNumber: z.string().min(1).max(16),
  departmentId: z.string().uuid(),
  rankId: z.string().uuid(),
  phone: z.string().max(20).optional(),
});

router.post(
  "/",
  requirePermission("admin", "manage_officers"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createOfficerSchema.parse(req.body);

    const officer = await prisma.officer.create({
      data: {
        userId: body.userId,
        firstName: sanitizeString(body.firstName),
        lastName: sanitizeString(body.lastName),
        badgeNumber: body.badgeNumber.toUpperCase(),
        departmentId: body.departmentId,
        rankId: body.rankId,
        phone: body.phone,
      },
    });

    res.status(201).json(officer);
  })
);

// ============================================================
// PATCH /api/officers/:id - Update officer
// ============================================================
router.patch(
  "/:id",
  requirePermission("admin", "manage_officers"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = req.body;

    const officer = await prisma.officer.update({
      where: { id: req.params.id },
      data: {
        ...(body.firstName && { firstName: sanitizeString(body.firstName) }),
        ...(body.lastName && { lastName: sanitizeString(body.lastName) }),
        ...(body.badgeNumber && { badgeNumber: body.badgeNumber.toUpperCase() }),
        ...(body.departmentId && { departmentId: body.departmentId }),
        ...(body.rankId && { rankId: body.rankId }),
        ...(body.phone && { phone: body.phone }),
        ...(body.callsign !== undefined && { callsign: body.callsign }),
        ...(body.imageUrl !== undefined && { imageUrl: body.imageUrl }),
      },
    });

    res.json(officer);
  })
);

export { router as officerRoutes };
