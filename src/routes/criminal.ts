import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString, parsePagination, paginatedResponse, generateReportNumber, dateTimeField, optionalDateTimeField } from "../utils/helpers";
import { requirePermission } from "../middleware/auth";
import { z } from "zod";

const router = Router();

// ============================================================
// ARRESTS
// ============================================================

router.get(
  "/arrests",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const civilianId = req.query.civilianId as string | undefined;
    const officerId = req.query.officerId as string | undefined;

    const where: any = {};
    if (civilianId) where.civilianId = civilianId;
    if (officerId) where.officerId = officerId;

    const [arrests, total] = await Promise.all([
      prisma.arrestReport.findMany({
        where,
        include: {
          officer: { select: { firstName: true, lastName: true, badgeNumber: true } },
          civilian: { select: { firstName: true, lastName: true, dateOfBirth: true } },
        },
        skip,
        take: limit,
        orderBy: { dateTime: "desc" },
      }),
      prisma.arrestReport.count({ where }),
    ]);

    res.json(paginatedResponse(arrests, total, page, limit));
  })
);

const createArrestSchema = z.object({
  officerId: z.string().uuid(),
  civilianId: z.string().uuid(),
  location: z.string().min(1).max(255),
  dateTime: dateTimeField,
  narrative: z.string().min(1).max(10000),
  charges: z.array(z.string()).min(1),
  jailTimeDays: z.number().int().min(0).optional(),
  mirandaRead: z.boolean().optional(),
});

router.post(
  "/arrests",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createArrestSchema.parse(req.body);

    const arrest = await prisma.arrestReport.create({
      data: {
        reportNumber: generateReportNumber("ARR"),
        officerId: body.officerId,
        civilianId: body.civilianId,
        location: sanitizeString(body.location),
        dateTime: new Date(body.dateTime),
        narrative: sanitizeString(body.narrative),
        charges: JSON.stringify(body.charges),
        jailTimeDays: body.jailTimeDays ?? null,
        mirandaRead: body.mirandaRead ?? false,
      },
    });

    res.status(201).json(arrest);
  })
);

// ============================================================
// CITATIONS
// ============================================================

router.get(
  "/citations",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const civilianId = req.query.civilianId as string | undefined;

    const where: any = {};
    if (civilianId) where.civilianId = civilianId;

    const [citations, total] = await Promise.all([
      prisma.citation.findMany({
        where,
        include: {
          officer: { select: { firstName: true, lastName: true } },
          civilian: { select: { firstName: true, lastName: true } },
        },
        skip,
        take: limit,
        orderBy: { dateTime: "desc" },
      }),
      prisma.citation.count({ where }),
    ]);

    res.json(paginatedResponse(citations, total, page, limit));
  })
);

const createCitationSchema = z.object({
  officerId: z.string().uuid(),
  civilianId: z.string().uuid(),
  location: z.string().min(1).max(255),
  dateTime: dateTimeField,
  violation: z.string().min(1).max(255),
  amount: z.number().optional(),
  description: z.string().max(5000).optional(),
});

router.post(
  "/citations",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createCitationSchema.parse(req.body);

    const citation = await prisma.citation.create({
      data: {
        citationNumber: generateReportNumber("CIT"),
        officerId: body.officerId,
        civilianId: body.civilianId,
        location: sanitizeString(body.location),
        dateTime: new Date(body.dateTime),
        violation: sanitizeString(body.violation),
        amount: body.amount,
        description: body.description ? sanitizeString(body.description) : null,
      },
    });

    res.status(201).json(citation);
  })
);

// ============================================================
// WARNINGS
// ============================================================

router.get(
  "/warnings",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const civilianId = req.query.civilianId as string | undefined;

    const where: any = {};
    if (civilianId) where.civilianId = civilianId;

    const [warnings, total] = await Promise.all([
      prisma.warning.findMany({
        where,
        include: {
          officer: { select: { firstName: true, lastName: true } },
          civilian: { select: { firstName: true, lastName: true } },
        },
        skip,
        take: limit,
        orderBy: { dateTime: "desc" },
      }),
      prisma.warning.count({ where }),
    ]);

    res.json(paginatedResponse(warnings, total, page, limit));
  })
);

const createWarningSchema = z.object({
  officerId: z.string().uuid(),
  civilianId: z.string().uuid(),
  type: z.string().min(1).max(64),
  description: z.string().min(1).max(5000),
  location: z.string().max(255).optional(),
  dateTime: dateTimeField,
});

router.post(
  "/warnings",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createWarningSchema.parse(req.body);

    const warning = await prisma.warning.create({
      data: {
        officerId: body.officerId,
        civilianId: body.civilianId,
        type: sanitizeString(body.type),
        description: sanitizeString(body.description),
        location: body.location ? sanitizeString(body.location) : null,
        dateTime: new Date(body.dateTime),
      },
    });

    res.status(201).json(warning);
  })
);

// ============================================================
// WARRANTS
// ============================================================

router.get(
  "/warrants",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const status = req.query.status as string | undefined;

    const where: any = {};
    if (status) where.status = status;

    const [warrants, total] = await Promise.all([
      prisma.warrant.findMany({
        where,
        include: {
          civilian: { select: { id: true, firstName: true, lastName: true, dateOfBirth: true } },
        },
        skip,
        take: limit,
        orderBy: { issuedAt: "desc" },
      }),
      prisma.warrant.count({ where }),
    ]);

    res.json(paginatedResponse(warrants, total, page, limit));
  })
);

const createWarrantSchema = z.object({
  civilianId: z.string().uuid(),
  type: z.string().min(1).max(64),
  charges: z.string().min(1).max(5000),
  issuedBy: z.string().min(1).max(128),
  issuedAt: dateTimeField,
  expiresAt: optionalDateTimeField,
  notes: z.string().max(5000).optional(),
});

router.post(
  "/warrants",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createWarrantSchema.parse(req.body);

    const warrant = await prisma.warrant.create({
      data: {
        warrantNumber: generateReportNumber("WAR"),
        civilianId: body.civilianId,
        type: sanitizeString(body.type),
        charges: sanitizeString(body.charges),
        issuedBy: sanitizeString(body.issuedBy),
        issuedAt: new Date(body.issuedAt),
        expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
        notes: body.notes ? sanitizeString(body.notes) : null,
      },
    });

    res.status(201).json(warrant);
  })
);

router.patch(
  "/warrants/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const { status, notes } = req.body;

    const warrant = await prisma.warrant.update({
      where: { id: req.params.id },
      data: {
        ...(status && { status }),
        ...(notes !== undefined && { notes: sanitizeString(notes) }),
      },
    });

    res.json(warrant);
  })
);

// ============================================================
// DELETE endpoints (admin only)
// ============================================================

router.delete(
  "/arrests/:id",
  requirePermission("admin", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.arrestReport.delete({ where: { id: req.params.id } });
    res.json({ message: "Arrest report deleted." });
  })
);

router.delete(
  "/citations/:id",
  requirePermission("admin", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.citation.delete({ where: { id: req.params.id } });
    res.json({ message: "Citation deleted." });
  })
);

router.delete(
  "/warnings/:id",
  requirePermission("admin", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.warning.delete({ where: { id: req.params.id } });
    res.json({ message: "Warning deleted." });
  })
);

export { router as criminalRoutes };
