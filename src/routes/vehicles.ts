import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString, parsePagination, paginatedResponse, isValidPlate } from "../utils/helpers";
import { requirePermission } from "../middleware/auth";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/vehicles - Search vehicles
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const search = req.query.search ? String(req.query.search) : '';
    const plate = req.query.plate ? String(req.query.plate) : '';
    const stolen = req.query.stolen ? String(req.query.stolen) : '';

    const where: any = {};

    if (plate) {
      where.plate = { contains: plate.toUpperCase() };
    } else if (search) {
      where.OR = [
        { plate: { contains: search.toUpperCase() } },
        { model: { contains: search } },
        { color: { contains: search } },
      ];
    }

    if (stolen === "true") where.stolen = true;

    const [vehicles, total] = await Promise.all([
      prisma.vehicle.findMany({
        where,
        include: {
          owner: {
            select: {
              id: true, firstName: true, lastName: true,
              dateOfBirth: true,
            },
          },
        },
        skip,
        take: limit,
        orderBy: { plate: "asc" },
      }),
      prisma.vehicle.count({ where }),
    ]);

    res.json(paginatedResponse(vehicles, total, page, limit));
  })
);

// ============================================================
// GET /api/vehicles/plate/:plate - Quick plate lookup
// ============================================================
router.get(
  "/plate/:plate",
  asyncHandler(async (req: Request, res: Response) => {
    const plate = String(req.params.plate).toUpperCase().trim();

    const vehicle = await prisma.vehicle.findUnique({
      where: { plate },
      include: {
        owner: {
          include: {
            licenses: { where: { type: "drivers" } },
            warrants: { where: { status: "ACTIVE" } },
          },
        },
      },
    });

    if (!vehicle) {
      return res.json({
        found: false,
        plate,
        message: "No vehicle found with this plate.",
      });
    }

    // Build response with flags
    const flags: string[] = [];
    if (vehicle.stolen) flags.push("STOLEN VEHICLE");
    if (vehicle.owner.warrants.length > 0) flags.push("OWNER HAS ACTIVE WARRANTS");
    if (vehicle.registrationStatus === "EXPIRED") flags.push("EXPIRED REGISTRATION");
    if (vehicle.insuranceStatus === "EXPIRED") flags.push("EXPIRED INSURANCE");
    if (vehicle.flags) {
      try {
        const parsed = JSON.parse(vehicle.flags);
        if (Array.isArray(parsed)) flags.push(...parsed);
      } catch { /* ignore */ }
    }

    res.json({
      found: true,
      vehicle: {
        id: vehicle.id,
        plate: vehicle.plate,
        model: vehicle.model,
        color: vehicle.color,
        year: vehicle.year,
        registrationStatus: vehicle.registrationStatus,
        insuranceStatus: vehicle.insuranceStatus,
        stolen: vehicle.stolen,
      },
      owner: vehicle.owner
        ? {
            id: vehicle.owner.id,
            name: `${vehicle.owner.firstName} ${vehicle.owner.lastName}`,
            dateOfBirth: vehicle.owner.dateOfBirth,
            licenses: vehicle.owner.licenses,
          }
        : null,
      flags,
    });
  })
);

// ============================================================
// GET /api/vehicles/:id - Vehicle detail
router.get(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const vehicle = await prisma.vehicle.findUnique({
      where: { id: req.params.id },
      include: {
        owner: {
          include: {
            licenses: true,
            warrants: { where: { status: "ACTIVE" } },
            arrests: {
              include: { officer: { select: { firstName: true, lastName: true } } },
              orderBy: { dateTime: "desc" },
              take: 5,
            },
            _count: { select: { citations: true, warnings: true } },
          },
        },
      },
    });

    if (!vehicle) throw createError(404, "Vehicle not found.");

    // Build flags
    const flags: string[] = [];
    if (vehicle.stolen) flags.push("STOLEN VEHICLE");
    if (vehicle.owner?.warrants?.length) flags.push("OWNER HAS ACTIVE WARRANTS");
    if (vehicle.registrationStatus === "EXPIRED") flags.push("EXPIRED REGISTRATION");
    if (vehicle.insuranceStatus === "EXPIRED") flags.push("EXPIRED INSURANCE");
    if (vehicle.flags) {
      try {
        const parsed = JSON.parse(vehicle.flags);
        if (Array.isArray(parsed)) flags.push(...parsed);
      } catch { /* ignore */ }
    }

    res.json({ vehicle, flags });
  })
);

// POST /api/vehicles - Create vehicle
// ============================================================
const createVehicleSchema = z.object({
  plate: z.string().min(1).max(16),
  model: z.string().min(1).max(64),
  color: z.string().min(1).max(32),
  year: z.number().int().min(1900).max(2030).optional(),
  vin: z.string().max(32).optional(),
  ownerId: z.string().uuid(),
});

router.post(
  "/",
  requirePermission("edit_vehicle_db", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createVehicleSchema.parse(req.body);

    const vehicle = await prisma.vehicle.create({
      data: {
        plate: body.plate.toUpperCase(),
        model: sanitizeString(body.model),
        color: sanitizeString(body.color),
        year: body.year,
        vin: body.vin?.toUpperCase(),
        ownerId: body.ownerId,
      },
    });

    res.status(201).json(vehicle);
  })
);

// ============================================================
// PATCH /api/vehicles/:id - Update vehicle
// ============================================================
router.patch(
  "/:id",
  requirePermission("edit_vehicle_db", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = req.body;

    const vehicle = await prisma.vehicle.update({
      where: { id: req.params.id },
      data: {
        ...(body.model && { model: sanitizeString(body.model) }),
        ...(body.color && { color: sanitizeString(body.color) }),
        ...(body.year && { year: body.year }),
        ...(body.registrationStatus && { registrationStatus: body.registrationStatus as any }),
        ...(body.insuranceStatus && { insuranceStatus: body.insuranceStatus as any }),
        ...(body.stolen !== undefined && { stolen: body.stolen }),
        ...(body.notes !== undefined && {
          notes: body.notes ? sanitizeString(body.notes) : null,
        }),
      },
    });

    res.json(vehicle);
  })
);

export { router as vehicleRoutes };
