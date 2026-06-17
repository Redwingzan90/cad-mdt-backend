import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString, parsePagination, paginatedResponse, generateReportNumber } from "../utils/helpers";
import { requirePermission } from "../middleware/auth";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/evidence - List evidence
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const caseType = req.query.caseType as string | undefined;
    const caseId = req.query.caseId as string | undefined;
    const officerId = req.query.officerId as string | undefined;

    const where: any = {};
    if (caseType) where.caseType = caseType;
    if (caseId) where.caseId = caseId;
    if (officerId) where.officerId = officerId;

    const [items, total] = await Promise.all([
      prisma.evidence.findMany({
        where,
        include: {
          officer: {
            select: { id: true, firstName: true, lastName: true, badgeNumber: true },
          },
        },
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
      }),
      prisma.evidence.count({ where }),
    ]);

    res.json(paginatedResponse(items, total, page, limit));
  })
);

// ============================================================
// POST /api/evidence - Add evidence
// ============================================================
const createEvidenceSchema = z.object({
  type: z.enum(["IMAGE", "VIDEO", "DOCUMENT", "NOTE", "OTHER"]),
  title: z.string().min(1).max(255),
  description: z.string().max(10000).optional(),
  fileUrl: z.string().max(512).optional(),
  fileName: z.string().max(255).optional(),
  fileSize: z.number().int().optional(),
  officerId: z.string().uuid(),
  caseType: z.string().max(32).optional(),
  caseId: z.string().uuid().optional(),
});

router.post(
  "/",
  requirePermission("manage_evidence", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createEvidenceSchema.parse(req.body);

    const evidence = await prisma.evidence.create({
      data: {
        evidenceNumber: generateReportNumber("EVD"),
        type: body.type as any,
        title: sanitizeString(body.title),
        description: body.description ? sanitizeString(body.description) : null,
        fileUrl: body.fileUrl,
        fileName: body.fileName,
        fileSize: body.fileSize,
        officerId: body.officerId,
        caseType: body.caseType,
        caseId: body.caseId,
      },
    });

    res.status(201).json(evidence);
  })
);

// ============================================================
// GET /api/evidence/:id
// ============================================================
router.get(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const item = await prisma.evidence.findUnique({
      where: { id: req.params.id },
      include: {
        officer: {
          select: { firstName: true, lastName: true, badgeNumber: true },
        },
      },
    });

    if (!item) throw createError(404, "Evidence not found.");
    res.json(item);
  })
);

// ============================================================
// DELETE /api/evidence/:id
// ============================================================
router.delete(
  "/:id",
  requirePermission("manage_evidence", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.evidence.delete({ where: { id: req.params.id } });
    res.json({ message: "Evidence deleted." });
  })
);

export { router as evidenceRoutes };
