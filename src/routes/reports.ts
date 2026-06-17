import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { requirePermission } from "../middleware/auth";
import { sanitizeString, parsePagination, paginatedResponse, generateReportNumber, dateTimeField } from "../utils/helpers";
import { z } from "zod";

const router = Router();

// ============================================================
// INCIDENT REPORTS
// ============================================================

router.get(
  "/incidents",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const status = req.query.status ? String(req.query.status) : undefined;

    const where: any = {};
    if (status) where.status = status;

    const [reports, total] = await Promise.all([
      prisma.incidentReport.findMany({
        where,
        include: {
          officer: { select: { firstName: true, lastName: true, badgeNumber: true } },
        },
        skip,
        take: limit,
        orderBy: { dateTime: "desc" },
      }),
      prisma.incidentReport.count({ where }),
    ]);

    res.json(paginatedResponse(reports, total, page, limit));
  })
);

router.get(
  "/incidents/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const report = await prisma.incidentReport.findUnique({
      where: { id: req.params.id },
      include: {
        officer: true,
        civilians: true,
        evidenceItems: true,
      },
    });
    if (!report) throw createError(404, "Report not found.");
    res.json(report);
  })
);

const createIncidentSchema = z.object({
  officerId: z.string().uuid(),
  location: z.string().min(1).max(255),
  dateTime: dateTimeField,
  type: z.string().min(1).max(64),
  narrative: z.string().min(1).max(20000),
});

router.post(
  "/incidents",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createIncidentSchema.parse(req.body);

    const report = await prisma.incidentReport.create({
      data: {
        reportNumber: generateReportNumber("INC"),
        officerId: body.officerId,
        location: sanitizeString(body.location),
        dateTime: new Date(body.dateTime),
        type: sanitizeString(body.type),
        narrative: sanitizeString(body.narrative),
        status: "DRAFT",
      },
    });

    res.status(201).json(report);
  })
);

router.patch(
  "/incidents/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const body = req.body;

    const updateData: any = {};
    if (body.location) updateData.location = sanitizeString(body.location);
    if (body.type) updateData.type = sanitizeString(body.type);
    if (body.narrative) updateData.narrative = sanitizeString(body.narrative);
    if (body.status) updateData.status = body.status;
    if (body.status === "APPROVED") {
      updateData.approvedBy = req.user!.username;
      updateData.approvedAt = new Date();
    }
    if (body.signatureData) updateData.signatureData = body.signatureData;

    const report = await prisma.incidentReport.update({
      where: { id: req.params.id },
      data: updateData,
    });

    res.json(report);
  })
);

// ============================================================
// CRASH REPORTS
// ============================================================

router.get(
  "/crashes",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);

    const [reports, total] = await Promise.all([
      prisma.crashReport.findMany({
        include: {
          officer: { select: { firstName: true, lastName: true, badgeNumber: true } },
          vehicles: { include: { vehicle: true } },
        },
        skip,
        take: limit,
        orderBy: { dateTime: "desc" },
      }),
      prisma.crashReport.count(),
    ]);

    res.json(paginatedResponse(reports, total, page, limit));
  })
);

router.get(
  "/crashes/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const report = await prisma.crashReport.findUnique({
      where: { id: req.params.id },
      include: {
        officer: true,
        vehicles: { include: { vehicle: true } },
      },
    });
    if (!report) throw createError(404, "Report not found.");
    res.json(report);
  })
);

const createCrashSchema = z.object({
  officerId: z.string().uuid(),
  location: z.string().min(1).max(255),
  dateTime: dateTimeField,
  narrative: z.string().min(1).max(20000),
  weather: z.string().max(32).optional(),
  roadConditions: z.string().max(64).optional(),
  injuries: z.boolean().optional(),
  fatalities: z.boolean().optional(),
});

router.post(
  "/crashes",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createCrashSchema.parse(req.body);

    const report = await prisma.crashReport.create({
      data: {
        reportNumber: generateReportNumber("CRH"),
        officerId: body.officerId,
        location: sanitizeString(body.location),
        dateTime: new Date(body.dateTime),
        narrative: sanitizeString(body.narrative),
        weather: body.weather,
        roadConditions: body.roadConditions,
        injuries: body.injuries ?? false,
        fatalities: body.fatalities ?? false,
        status: "DRAFT",
      },
    });

    res.status(201).json(report);
  })
);

// ============================================================
// USE OF FORCE REPORTS
// ============================================================

router.get(
  "/use-of-force",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);

    const [reports, total] = await Promise.all([
      prisma.useOfForceReport.findMany({
        include: {
          officer: { select: { firstName: true, lastName: true, badgeNumber: true } },
        },
        skip,
        take: limit,
        orderBy: { dateTime: "desc" },
      }),
      prisma.useOfForceReport.count(),
    ]);

    res.json(paginatedResponse(reports, total, page, limit));
  })
);

router.get(
  "/use-of-force/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const report = await prisma.useOfForceReport.findUnique({
      where: { id: req.params.id },
      include: { officer: true },
    });
    if (!report) throw createError(404, "Report not found.");
    res.json(report);
  })
);

const createUofSchema = z.object({
  officerId: z.string().uuid(),
  location: z.string().min(1).max(255),
  dateTime: dateTimeField,
  forceType: z.string().min(1).max(64),
  subjectName: z.string().min(1).max(128),
  narrative: z.string().min(1).max(20000),
  witnessInfo: z.string().max(10000).optional(),
  injuries: z.string().max(5000).optional(),
  medicalAttention: z.boolean().optional(),
});

router.post(
  "/use-of-force",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createUofSchema.parse(req.body);

    const report = await prisma.useOfForceReport.create({
      data: {
        reportNumber: generateReportNumber("UOF"),
        officerId: body.officerId,
        location: sanitizeString(body.location),
        dateTime: new Date(body.dateTime),
        forceType: sanitizeString(body.forceType),
        subjectName: sanitizeString(body.subjectName),
        narrative: sanitizeString(body.narrative),
        witnessInfo: body.witnessInfo ? sanitizeString(body.witnessInfo) : null,
        injuries: body.injuries ? sanitizeString(body.injuries) : null,
        medicalAttention: body.medicalAttention ?? false,
        status: "DRAFT",
      },
    });

    res.status(201).json(report);
  })
);

// ============================================================
// INVESTIGATION REPORTS
// ============================================================

router.get(
  "/investigations",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const status = req.query.status ? String(req.query.status) : undefined;

    const where: any = {};
    if (status) where.status = status;

    const [reports, total] = await Promise.all([
      prisma.investigationReport.findMany({
        where,
        include: {
          officer: { select: { firstName: true, lastName: true, badgeNumber: true } },
        },
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
      }),
      prisma.investigationReport.count({ where }),
    ]);

    res.json(paginatedResponse(reports, total, page, limit));
  })
);

router.get(
  "/investigations/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const report = await prisma.investigationReport.findUnique({
      where: { id: req.params.id },
      include: { officer: true, evidenceItems: true },
    });
    if (!report) throw createError(404, "Report not found.");
    res.json(report);
  })
);

const createInvestigationSchema = z.object({
  officerId: z.string().uuid(),
  title: z.string().min(1).max(255),
  description: z.string().min(1).max(20000),
  priority: z.number().int().min(1).max(5).optional(),
  startDate: dateTimeField,
});

router.post(
  "/investigations",
  asyncHandler(async (req: Request, res: Response) => {
    const body = createInvestigationSchema.parse(req.body);

    const report = await prisma.investigationReport.create({
      data: {
        reportNumber: generateReportNumber("INV"),
        officerId: body.officerId,
        title: sanitizeString(body.title),
        description: sanitizeString(body.description),
        priority: body.priority ?? 3,
        startDate: new Date(body.startDate),
        status: "OPEN",
      },
    });

    res.status(201).json(report);
  })
);

// ============================================================
// SUPERVISOR APPROVAL (generic for all report types)
// ============================================================

router.post(
  "/:type/:id/approve",
  requirePermission("supervisor", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const type = String(req.params.type);
    const id = String(req.params.id);
    const { signatureData } = req.body;

    const tableMap: Record<string, any> = {
      incidents: prisma.incidentReport,
      crashes: prisma.crashReport,
      "use-of-force": prisma.useOfForceReport,
      investigations: prisma.investigationReport,
    };

    const model = tableMap[type];
    if (!model) throw createError(400, "Invalid report type.");

    const report = await (model as any).update({
      where: { id },
      data: {
        status: "APPROVED",
        approvedBy: req.user!.username,
        approvedAt: new Date(),
        ...(signatureData && { signatureData }),
      },
    });

    res.json(report);
  })
);

// ============================================================
// DELETE REPORTS (admin only)
// ============================================================

router.delete(
  "/:type/:id",
  requirePermission("admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const type = String(req.params.type);
    const id = String(req.params.id);

    const tableMap: Record<string, any> = {
      incidents: prisma.incidentReport,
      crashes: prisma.crashReport,
      "use-of-force": prisma.useOfForceReport,
      investigations: prisma.investigationReport,
    };

    const model = tableMap[type];
    if (!model) throw createError(400, "Invalid report type.");

    await (model as any).delete({ where: { id } });

    res.json({ message: "Report deleted." });
  })
);

export { router as reportRoutes };
