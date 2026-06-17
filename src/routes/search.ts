import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";

const router = Router();

// ============================================================
// GET /api/search - Global search
// ============================================================
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    const query = req.query.q as string;
    if (!query || query.length < 2) {
      return res.json({ civilians: [], vehicles: [], officers: [], reports: [] });
    }

    const searchTerm = query.trim();

    const [civilians, vehicles, officers, reports] = await Promise.all([
      // Search civilians
      prisma.civilian.findMany({
        where: {
          active: true,
          OR: [
            { firstName: { contains: searchTerm } },
            { lastName: { contains: searchTerm } },
            { phone: { contains: searchTerm } },
          ],
        },
        select: {
          id: true, firstName: true, lastName: true,
          dateOfBirth: true, phone: true,
        },
        take: 10,
      }),

      // Search vehicles
      prisma.vehicle.findMany({
        where: {
          OR: [
            { plate: { contains: searchTerm.toUpperCase() } },
            { model: { contains: searchTerm } },
          ],
        },
        select: {
          id: true, plate: true, model: true, color: true, stolen: true,
          owner: { select: { firstName: true, lastName: true } },
        },
        take: 10,
      }),

      // Search officers
      prisma.officer.findMany({
        where: {
          active: true,
          OR: [
            { firstName: { contains: searchTerm } },
            { lastName: { contains: searchTerm } },
            { badgeNumber: { contains: searchTerm } },
            { callsign: { contains: searchTerm } },
          ],
        },
        select: {
          id: true, firstName: true, lastName: true,
          badgeNumber: true, callsign: true, status: true,
          department: { select: { name: true, code: true } },
        },
        take: 10,
      }),

      // Search reports
      prisma.incidentReport.findMany({
        where: {
          OR: [
            { reportNumber: { contains: searchTerm } },
            { narrative: { contains: searchTerm } },
            { location: { contains: searchTerm } },
          ],
        },
        select: {
          id: true, reportNumber: true, type: true,
          location: true, dateTime: true, status: true,
        },
        orderBy: { createdAt: "desc" },
        take: 10,
      }),
    ]);

    res.json({ civilians, vehicles, officers, reports });
  })
);

export { router as searchRoutes };
