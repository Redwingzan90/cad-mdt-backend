import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";
import { parsePagination, paginatedResponse } from "../utils/helpers";

const router = Router();

// ============================================================
// GET /api/notifications - List notifications
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const unreadOnly = req.query.unreadOnly === "true";

    const where: any = {
      OR: [
        { targetUserId: req.user!.id },
        { targetUserId: null }, // broadcast
      ],
    };
    if (unreadOnly) where.read = false;

    const [notifications, total] = await Promise.all([
      prisma.notification.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
      }),
      prisma.notification.count({ where }),
    ]);

    res.json(paginatedResponse(notifications, total, page, limit));
  })
);

// ============================================================
// GET /api/notifications/unread-count
// ============================================================
router.get(
  "/unread-count",
  asyncHandler(async (req: Request, res: Response) => {
    const count = await prisma.notification.count({
      where: {
        read: false,
        OR: [
          { targetUserId: req.user!.id },
          { targetUserId: null },
        ],
      },
    });

    res.json({ count });
  })
);

// ============================================================
// PATCH /api/notifications/:id/read
// ============================================================
router.patch(
  "/:id/read",
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.notification.update({
      where: { id: req.params.id },
      data: { read: true },
    });

    res.json({ message: "Marked as read." });
  })
);

// ============================================================
// PATCH /api/notifications/read-all
// ============================================================
router.patch(
  "/read-all",
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.notification.updateMany({
      where: {
        read: false,
        OR: [
          { targetUserId: req.user!.id },
          { targetUserId: null },
        ],
      },
      data: { read: true },
    });

    res.json({ message: "All notifications marked as read." });
  })
);

export { router as notificationRoutes };
