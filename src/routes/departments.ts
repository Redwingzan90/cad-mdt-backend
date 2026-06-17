import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";

const router = Router();

// ============================================================
// GET /api/departments - Public listing (no admin guard)
// Available to any authenticated user (dispatchers need this)
// ============================================================
router.get(
  "/",
  asyncHandler(async (_req: Request, res: Response) => {
    const departments = await prisma.department.findMany({
      where: { active: true },
      select: {
        id: true,
        name: true,
        code: true,
        color: true,
      },
      orderBy: { name: "asc" },
    });

    res.json(departments);
  })
);

export { router as departmentRoutes };
