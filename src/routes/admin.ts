import { Router, Request, Response } from "express";
import bcrypt from "bcryptjs";
import { prisma, io } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { requirePermission } from "../middleware/auth";
import { sanitizeString, parsePagination, paginatedResponse, optionalDateTimeField } from "../utils/helpers";
import { z } from "zod";

const router = Router();

// Note: admin permission is applied per-route below.
// This allows certain routes (promote/demote, announcements) to be
// accessible to supervisors and other roles with appropriate permissions.

// ============================================================
// USERS
// ============================================================

router.get(
  "/users",
  requirePermission("admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);

    const [users, total] = await Promise.all([
      prisma.user.findMany({
        include: {
          officer: {
            select: {
              id: true, firstName: true, lastName: true,
              badgeNumber: true, department: { select: { name: true } },
            },
          },
          permissions: {
            include: { permission: { select: { name: true } } },
          },
        },
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
      }),
      prisma.user.count(),
    ]);

    // Strip password hashes
    const safeUsers = users.map(({ passwordHash, ...rest }) => rest);

    res.json(paginatedResponse(safeUsers, total, page, limit));
  })
);

router.patch(
  "/users/:id",
  requirePermission("admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const { active, email } = req.body;

    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: {
        ...(active !== undefined && { active }),
        ...(email !== undefined && { email }),
      },
    });

    const { passwordHash, ...safe } = user as any;
    res.json(safe);
  })
);

const createUserSchema = z.object({
  username: z.string().min(3).max(64),
  password: z.string().min(8).max(128),
  email: z.preprocess(v => v === "" ? undefined : v, z.string().email().optional()),
  firstName: z.preprocess(v => v === "" ? undefined : v, z.string().min(1).max(64).optional()),
  lastName: z.preprocess(v => v === "" ? undefined : v, z.string().min(1).max(64).optional()),
  badgeNumber: z.preprocess(v => v === "" ? undefined : v, z.string().max(16).optional()),
  departmentId: z.preprocess(v => v === "" ? undefined : v, z.string().uuid().optional()),
  rankId: z.preprocess(v => v === "" ? undefined : v, z.string().uuid().optional()),
  callsign: z.preprocess(v => v === "" ? undefined : v, z.string().max(16).optional()),
});

router.post(
  "/users",
  requirePermission("admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createUserSchema.parse(req.body);

    const existing = await prisma.user.findUnique({ where: { username: body.username } });
    if (existing) throw createError(409, "Username already taken.");

    const passwordHash = await bcrypt.hash(body.password, 12);

    const user = await prisma.user.create({
      data: {
        username: body.username,
        passwordHash,
        email: body.email,
        ...(body.firstName && body.lastName && {
          officer: {
            create: {
              firstName: sanitizeString(body.firstName),
              lastName: sanitizeString(body.lastName),
              badgeNumber: body.badgeNumber || null,
              departmentId: body.departmentId || null,
              rankId: body.rankId || null,
              callsign: body.callsign || null,
            },
          },
        }),
      },
      include: {
        officer: {
          include: { department: { select: { name: true, code: true } }, rank: { select: { name: true } } },
        },
      },
    });

    const { passwordHash: _, ...safe } = user as any;
    res.status(201).json(safe);
  })
);

const assignOfficerSchema = z.object({
  firstName: z.preprocess(v => v === "" ? undefined : v, z.string().min(1).max(64).optional()),
  lastName: z.preprocess(v => v === "" ? undefined : v, z.string().min(1).max(64).optional()),
  badgeNumber: z.preprocess(v => v === "" ? undefined : v, z.string().max(16).optional()),
  departmentId: z.preprocess(v => v === "" ? undefined : v, z.string().uuid().optional()),
  rankId: z.preprocess(v => v === "" ? undefined : v, z.string().uuid().optional()),
  callsign: z.preprocess(v => v === "" ? undefined : v, z.string().max(16).optional()),
});

router.patch(
  "/users/:id/officer",
  requirePermission("admin", "manage_officers", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = assignOfficerSchema.parse(req.body);
    const user = await prisma.user.findUnique({
      where: { id: req.params.id },
      include: { officer: true },
    });
    if (!user) throw createError(404, "User not found.");

    if (!user.officer) {      // Create officer profile
      if (!body.firstName || !body.lastName) throw createError(400, "firstName and lastName required to create officer profile.");
      const officer = await prisma.officer.create({
        data: {
          userId: user.id,
          firstName: sanitizeString(body.firstName),
          lastName: sanitizeString(body.lastName),
          badgeNumber: body.badgeNumber || null,
          departmentId: body.departmentId || null,
          rankId: body.rankId || null,
          callsign: body.callsign || null,
        },
        include: { department: true, rank: true },
      });
      return res.json(officer);
    }    // Update existing officer
    // Auto-set roleId based on rank level when rankId changes
    let roleIdUpdate: any = {};
    if (body.rankId && body.rankId !== '') {
      const newRank = await prisma.rank.findUnique({ where: { id: body.rankId }, select: { level: true } });
      if (newRank) {
        const matchingRole = await prisma.role.findFirst({
          where: { level: { lte: newRank.level } },
          orderBy: { level: 'desc' },
          select: { id: true },
        });
        if (matchingRole) roleIdUpdate = { roleId: matchingRole.id };
      }
    }

    const officer = await prisma.officer.update({
      where: { id: user.officer.id },
      data: {
        ...(body.firstName && { firstName: sanitizeString(body.firstName) }),
        ...(body.lastName && { lastName: sanitizeString(body.lastName) }),
        ...(body.badgeNumber !== undefined && { badgeNumber: body.badgeNumber }),
        ...(body.departmentId !== undefined && body.departmentId !== '' && { departmentId: body.departmentId }),
        ...(body.rankId !== undefined && body.rankId !== '' && { rankId: body.rankId }),
        ...(body.callsign !== undefined && { callsign: body.callsign }),
        ...roleIdUpdate,
      },
      include: { department: true, rank: true },
    });

    res.json(officer);
  })
);

router.post(
  "/users/:id/reset-password",
  requirePermission("admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const { newPassword } = req.body;
    if (!newPassword || newPassword.length < 8) {
      throw createError(400, "Password must be at least 8 characters.");
    }

    const passwordHash = await bcrypt.hash(newPassword, 12);

    await prisma.user.update({
      where: { id: req.params.id },
      data: { passwordHash },
    });

    // Invalidate all sessions
    await prisma.session.deleteMany({ where: { userId: req.params.id } });

    res.json({ message: "Password reset successfully." });
  })
);

// ============================================================
// DEPARTMENTS
// ============================================================

router.get(
  "/departments",
  requirePermission("admin", "manage_departments", "supervisor"),
  asyncHandler(async (_req: Request, res: Response) => {
    const departments = await prisma.department.findMany({
      include: {
        _count: { select: { officers: true, calls: true } },
      },
      orderBy: { name: "asc" },
    });
    res.json(departments);
  })
);

const createDepartmentSchema = z.object({
  name: z.string().min(1).max(64),
  code: z.string().min(1).max(16),
  color: z.string().max(7).optional(),
});

router.post(
  "/departments",
  requirePermission("admin", "manage_departments"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createDepartmentSchema.parse(req.body);

    const dept = await prisma.department.create({
      data: {
        name: sanitizeString(body.name),
        code: body.code.toUpperCase(),
        color: body.color,
      },
    });

    res.status(201).json(dept);
  })
);

router.patch(
  "/departments/:id",
  requirePermission("admin", "manage_departments"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = req.body;

    const dept = await prisma.department.update({
      where: { id: req.params.id },
      data: {
        ...(body.name && { name: sanitizeString(body.name) }),
        ...(body.code && { code: body.code.toUpperCase() }),
        ...(body.color !== undefined && { color: body.color }),
        ...(body.active !== undefined && { active: body.active }),
      },
    });

    res.json(dept);
  })
);

// ============================================================
// RANKS
// ============================================================

router.get(
  "/ranks",
  requirePermission("admin", "manage_departments", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    const departmentId = req.query.departmentId as string | undefined;
    const where: any = {};
    if (departmentId) where.departmentId = departmentId;

    const ranks = await prisma.rank.findMany({
      where,
      include: {
        department: { select: { name: true, code: true } },
        _count: { select: { officers: true } },
      },
      orderBy: [{ departmentId: "asc" }, { level: "desc" }],
    });

    res.json(ranks);
  })
);

const createRankSchema = z.object({
  name: z.string().min(1).max(64),
  departmentId: z.string().uuid(),
  level: z.number().int().min(0).max(100),
  badgePrefix: z.string().max(8).optional(),
});

router.post(
  "/ranks",
  requirePermission("admin", "manage_departments"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createRankSchema.parse(req.body);

    const rank = await prisma.rank.create({
      data: {
        name: sanitizeString(body.name),
        departmentId: body.departmentId,
        level: body.level,
        badgePrefix: body.badgePrefix,
      },
    });

    res.status(201).json(rank);
  })
);

// ============================================================
// PERMISSIONS
// ============================================================

router.get(
  "/permissions",
  requirePermission("admin"),
  asyncHandler(async (_req: Request, res: Response) => {
    const permissions = await prisma.permission.findMany({
      orderBy: { name: "asc" },
    });
    res.json(permissions);
  })
);

const grantPermissionSchema = z.object({
  userId: z.string().uuid(),
  permissionId: z.string().uuid(),
  granted: z.boolean(),
});

router.post(
  "/permissions/grant",
  requirePermission("admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = grantPermissionSchema.parse(req.body);

    const perm = await prisma.userPermission.upsert({
      where: {
        userId_permissionId: {
          userId: body.userId,
          permissionId: body.permissionId,
        },
      },
      update: { granted: body.granted, grantedBy: req.user!.id },
      create: {
        userId: body.userId,
        permissionId: body.permissionId,
        granted: body.granted,
        grantedBy: req.user!.id,
      },
    });

    res.json(perm);
  })
);

// ============================================================
// AUDIT LOGS
// ============================================================

router.get(
  "/logs",
  requirePermission("admin", "view_audit_logs", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const action = req.query.action as string | undefined;
    const resource = req.query.resource as string | undefined;
    const userId = req.query.userId as string | undefined;

    const where: any = {};
    if (action) where.action = action;
    if (resource) where.resource = resource;
    if (userId) where.userId = userId;

    const [logs, total] = await Promise.all([
      prisma.auditLog.findMany({
        where,
        include: {
          user: { select: { id: true, username: true } },
        },
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
      }),
      prisma.auditLog.count({ where }),
    ]);

    res.json(paginatedResponse(logs, total, page, limit));
  })
);

// ============================================================
// PROMOTE / DEMOTE
// ============================================================

router.post(
  "/users/:id/promote",
  requirePermission("admin", "manage_officers", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    const { rankId } = req.body;
    if (!rankId) throw createError(400, "rankId is required.");

    const targetUser = await prisma.user.findUnique({
      where: { id: req.params.id },
      include: {
        officer: { include: { rank: true, department: true } },
      },
    });
    if (!targetUser?.officer) throw createError(404, "Officer profile not found.");

    const newRank = await prisma.rank.findUnique({
      where: { id: rankId },
      include: { department: true },
    });
    if (!newRank) throw createError(404, "Target rank not found.");

    // Get the requesting user's officer rank level
    const requesterOfficer = await prisma.officer.findUnique({
      where: { userId: req.user!.id },
      include: { rank: true },
    });
    const requesterLevel = requesterOfficer?.rank?.level ?? 0;
    const currentLevel = targetUser.officer.rank?.level ?? 0;

    // Must outrank both the current rank and the target rank
    if (requesterLevel <= currentLevel || requesterLevel < newRank.level) {
      throw createError(403, "You can only promote officers to ranks below your own.");
    }

    // Auto-set roleId based on new rank level
    let roleIdUpdate: any = {};
    const matchingRole = await prisma.role.findFirst({
      where: { level: { lte: newRank.level } },
      orderBy: { level: 'desc' },
      select: { id: true },
    });
    if (matchingRole) roleIdUpdate = { roleId: matchingRole.id };

    const officer = await prisma.officer.update({
      where: { id: targetUser.officer.id },
      data: { rankId: newRank.id, ...roleIdUpdate },
      include: { rank: true, department: true },
    });

    // Audit log
    await prisma.auditLog.create({
      data: {
        userId: req.user!.id,
        action: "PROMOTE",
        resource: "officer",
        resourceId: officer.id,
        details: JSON.stringify({ from: targetUser.officer.rank?.name, to: newRank.name }),
      },
    });

    res.json({ message: `Promoted to ${newRank.name}`, officer });
  })
);

router.post(
  "/users/:id/demote",
  requirePermission("admin", "manage_officers", "supervisor"),
  asyncHandler(async (req: Request, res: Response) => {
    const { rankId } = req.body;
    if (!rankId) throw createError(400, "rankId is required.");

    const targetUser = await prisma.user.findUnique({
      where: { id: req.params.id },
      include: {
        officer: { include: { rank: true, department: true } },
      },
    });
    if (!targetUser?.officer) throw createError(404, "Officer profile not found.");

    const newRank = await prisma.rank.findUnique({ where: { id: rankId } });
    if (!newRank) throw createError(404, "Target rank not found.");

    const requesterOfficer = await prisma.officer.findUnique({
      where: { userId: req.user!.id },
      include: { rank: true },
    });
    const requesterLevel = requesterOfficer?.rank?.level ?? 0;
    const currentLevel = targetUser.officer.rank?.level ?? 0;

    // Must outrank the current rank
    if (requesterLevel <= currentLevel) {
      throw createError(403, "You can only demote officers ranked below you.");
    }

    // Auto-set roleId based on new rank level
    let roleIdUpdateDemote: any = {};
    const matchingRoleDemote = await prisma.role.findFirst({
      where: { level: { lte: newRank.level } },
      orderBy: { level: 'desc' },
      select: { id: true },
    });
    if (matchingRoleDemote) roleIdUpdateDemote = { roleId: matchingRoleDemote.id };

    const officer = await prisma.officer.update({
      where: { id: targetUser.officer.id },
      data: { rankId: newRank.id, ...roleIdUpdateDemote },
      include: { rank: true, department: true },
    });

    await prisma.auditLog.create({
      data: {
        userId: req.user!.id,
        action: "DEMOTE",
        resource: "officer",
        resourceId: officer.id,
        details: JSON.stringify({ from: targetUser.officer.rank?.name, to: newRank.name }),
      },
    });

    res.json({ message: `Demoted to ${newRank.name}`, officer });
  })
);

// ============================================================
// ANNOUNCEMENTS
// ============================================================

// Announcements: any authenticated user can read (no extra permission needed)
router.get(
  "/announcements",
  asyncHandler(async (_req: Request, res: Response) => {
    const announcements = await prisma.announcement.findMany({
      where: {
        active: true,
        OR: [
          { expiresAt: null },
          { expiresAt: { gt: new Date() } },
        ],
      },
      orderBy: { createdAt: "desc" },
    });
    res.json(announcements);
  })
);

const createAnnouncementSchema = z.object({
  title: z.string().min(1).max(255),
  content: z.string().min(1).max(10000),
  priority: z.enum(["LOW", "NORMAL", "HIGH", "URGENT"]).default("NORMAL"),
  expiresAt: optionalDateTimeField,
});

router.post(
  "/announcements",
  requirePermission("admin", "manage_announcements"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createAnnouncementSchema.parse(req.body);

    const announcement = await prisma.announcement.create({
      data: {
        title: sanitizeString(body.title),
        content: sanitizeString(body.content),
        priority: body.priority,
        createdBy: req.user!.username,
        expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
      },
    });

    // Create a notification and broadcast to all connected users
    const notifPriority = body.priority;
    await prisma.notification.create({
      data: {
        type: "SYSTEM",
        title: `Announcement: ${announcement.title}`,
        message: announcement.content.slice(0, 500),
        priority: notifPriority as any,
      },
    });

    io.to("notifications").emit("notification:new", {
      id: announcement.id,
      type: "SYSTEM",
      title: `Announcement: ${announcement.title}`,
      message: announcement.content.slice(0, 500),
      priority: notifPriority,
      read: false,
      createdAt: announcement.createdAt,
    });

    res.status(201).json(announcement);
  })
);

router.delete(
  "/announcements/:id",
  requirePermission("admin", "manage_announcements"),
  asyncHandler(async (req: Request, res: Response) => {
    await prisma.announcement.update({
      where: { id: req.params.id },
      data: { active: false },
    });
    res.json({ message: "Announcement removed." });
  })
);

export { router as adminRoutes };
