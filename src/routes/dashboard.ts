import { Router, Request, Response } from "express";
import { prisma } from "../index";
import { asyncHandler } from "./base";

const router = Router();

// ============================================================
// GET /api/dashboard - Full dashboard data
// ============================================================
router.get(
  "/",
  asyncHandler(async (_req: Request, res: Response) => {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const [
      activeOfficers,
      activeCalls,
      activeBolos,
      activeWarrants,
      pendingEmergencies,
      announcements,
      recentReports,
      todayStats,
    ] = await Promise.all([
      // Active officers
      prisma.officer.findMany({
        where: { active: true, status: { not: "OFF_DUTY" } },
        take: 200,
        include: {
          department: { select: { name: true, code: true, color: true } },
          rank: { select: { name: true, level: true } },
          unit: { select: { callsign: true, status: true, vehicle: true } },
        },
        orderBy: [{ callsign: "asc" }],
      }),

      // Active dispatch calls
      prisma.dispatchCall.findMany({
        where: { status: { notIn: ["COMPLETED", "CANCELLED"] } },
        include: {
          department: { select: { name: true, code: true } },
          assignments: {
            include: {
              officer: {
                select: { firstName: true, lastName: true, callsign: true },
              },
            },
          },
        },
        orderBy: [{ priority: "asc" }, { createdAt: "desc" }],
      }),

      // Active BOLOs
      prisma.bolo.findMany({
        where: {
          active: true,
          OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        },
        include: {
          creator: { select: { firstName: true, lastName: true, callsign: true } },
          targetCiv: { select: { firstName: true, lastName: true } },
          targetVehicle: { select: { plate: true, model: true, color: true } },
        },
        orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
        take: 20,
      }),

      // Active warrants
      prisma.warrant.findMany({
        where: { status: "ACTIVE" },
        include: {
          civilian: { select: { firstName: true, lastName: true, dateOfBirth: true } },
        },
        orderBy: { issuedAt: "desc" },
        take: 20,
      }),

      // Pending 911 calls
      prisma.emergencyCall.findMany({
        where: { status: "PENDING" },
        orderBy: { createdAt: "desc" },
        take: 10,
      }),

      // Active announcements
      prisma.announcement.findMany({
        where: {
          active: true,
          OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        },
        orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
        take: 10,
      }),

      // Recent reports
      prisma.incidentReport.findMany({
        include: {
          officer: { select: { firstName: true, lastName: true } },
        },
        orderBy: { createdAt: "desc" },
        take: 10,
      }),

      // Today's stats
      Promise.all([
        prisma.dispatchCall.count({ where: { createdAt: { gte: todayStart } } }),
        prisma.emergencyCall.count({ where: { createdAt: { gte: todayStart } } }),
        prisma.arrestReport.count({ where: { createdAt: { gte: todayStart } } }),
        prisma.citation.count({ where: { createdAt: { gte: todayStart } } }),
      ]),
    ]);

    res.json({
      activeOfficers,
      activeCalls,
      activeBolos,
      activeWarrants,
      pendingEmergencies,
      announcements,
      recentReports,
      stats: {
        callsToday: todayStats[0],
        emergenciesToday: todayStats[1],
        arrestsToday: todayStats[2],
        citationsToday: todayStats[3],
        officersOnDuty: activeOfficers.length,
        activeCallsCount: activeCalls.length,
      },
    });
  })
);

export { router as dashboardRoutes };
