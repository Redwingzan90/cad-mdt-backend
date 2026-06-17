import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString, parsePagination, paginatedResponse } from "../utils/helpers";
import { requirePermission } from "../middleware/auth";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/civilians - Search civilians
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const search = req.query.search as string | undefined;
    const firstName = req.query.firstName as string | undefined;
    const lastName = req.query.lastName as string | undefined;

    const where: any = { active: true };

    if (search) {
      where.OR = [
        { firstName: { contains: search } },
        { lastName: { contains: search } },
        { phone: { contains: search } },
      ];
    }
    if (firstName) where.firstName = { contains: firstName };
    if (lastName) where.lastName = { contains: lastName };

    // Non-admin/non-supervisor users only see their own characters
    if (!req.user!.permissions.includes('admin') && !req.user!.permissions.includes('supervisor')) {
      where.playerIdentifier = req.user!.username;
    }

    const [civilians, total] = await Promise.all([
      prisma.civilian.findMany({
        where,
        include: {
          licenses: { select: { type: true, status: true } },
          vehicles: { select: { plate: true, model: true, stolen: true } },
          warrants: { where: { status: "ACTIVE" }, select: { id: true } },
          _count: { select: { citations: true, warnings: true } },
        },
        skip,
        take: limit,
        orderBy: [{ lastName: "asc" }, { firstName: "asc" }],
      }),
      prisma.civilian.count({ where }),
    ]);

    // Flatten counts into the response for the frontend
    const enriched = civilians.map(({ _count, ...civ }: any) => ({
      ...civ,
      _citationCount: _count?.citations ?? 0,
      _warningCount: _count?.warnings ?? 0,
    }));

    res.json(paginatedResponse(enriched, total, page, limit));
  })
);

// ============================================================
// GET /api/civilians/:id - Full civilian profile
// ============================================================
router.get(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const civilian = await prisma.civilian.findUnique({
      where: { id: req.params.id },
      include: {
        licenses: true,
        vehicles: true,
        arrests: {
          include: { officer: { select: { firstName: true, lastName: true, badgeNumber: true } } },
          orderBy: { dateTime: "desc" },
          take: 20,
        },
        citations: {
          include: { officer: { select: { firstName: true, lastName: true } } },
          orderBy: { dateTime: "desc" },
          take: 20,
        },
        warnings: {
          include: { officer: { select: { firstName: true, lastName: true } } },
          orderBy: { dateTime: "desc" },
          take: 20,
        },
        warrants: { orderBy: { issuedAt: "desc" } },
      },
    });

    if (!civilian) throw createError(404, "Civilian not found.");
    res.json(civilian);
  })
);

// ============================================================
// POST /api/civilians - Create civilian
// ============================================================
const createCivilianSchema = z.object({
  firstName: z.string().min(1).max(64),
  lastName: z.string().min(1).max(64),
  dateOfBirth: z.string().min(1), // Accept any date string (YYYY-MM-DD from HTML date input or ISO datetime)
  gender: z.string().max(16).optional(),
  ethnicity: z.string().max(32).optional(),
  address: z.string().max(255).optional(),
  phone: z.string().max(20).optional(),
});

router.post(
  "/",
  requirePermission("edit_civilian_db", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createCivilianSchema.parse(req.body);

    // Link civilian to the logged-in FiveM user so it appears as their character in-game
    const playerIdentifier = req.user!.username;

    // Deactivate any existing active character for this user
    await prisma.civilian.updateMany({
      where: { playerIdentifier, isActive: true },
      data: { isActive: false },
    });

    const civilian = await prisma.civilian.create({
      data: {
        firstName: sanitizeString(body.firstName),
        lastName: sanitizeString(body.lastName),
        dateOfBirth: new Date(body.dateOfBirth),
        gender: body.gender,
        ethnicity: body.ethnicity,
        address: body.address ? sanitizeString(body.address) : undefined,
        phone: body.phone,
        playerIdentifier,
        isActive: true,
      },
    });

    res.status(201).json(civilian);
  })
);

// ============================================================
// PATCH /api/civilians/:id - Update civilian
// ============================================================
router.patch(
  "/:id",
  requirePermission("edit_civilian_db", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = req.body;

    const civilian = await prisma.civilian.update({
      where: { id: req.params.id },
      data: {
        ...(body.firstName && { firstName: sanitizeString(body.firstName) }),
        ...(body.lastName && { lastName: sanitizeString(body.lastName) }),
        ...(body.dateOfBirth && { dateOfBirth: new Date(body.dateOfBirth) }),
        ...(body.gender !== undefined && { gender: body.gender }),
        ...(body.ethnicity !== undefined && { ethnicity: body.ethnicity }),
        ...(body.address !== undefined && {
          address: body.address ? sanitizeString(body.address) : null,
        }),
        ...(body.phone !== undefined && { phone: body.phone }),
        ...(body.notes !== undefined && {
          notes: body.notes ? sanitizeString(body.notes) : null,
        }),
      },
    });

    res.json(civilian);
  })
);

// ============================================================
// DELETE /api/civilians/:id - Soft-delete civilian (admin only)
// ============================================================
router.delete(
  "/:id",
  requirePermission("admin", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    const civilian = await prisma.civilian.findUnique({
      where: { id: req.params.id },
      select: { id: true, active: true },
    });
    if (!civilian) throw createError(404, "Civilian not found.");

    await prisma.civilian.update({
      where: { id: req.params.id },
      data: { active: false },
    });

    res.json({ message: "Civilian deleted successfully." });
  })
);

export { router as civilianRoutes };
