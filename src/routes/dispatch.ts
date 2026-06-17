import { Router, Request, Response } from "express";
import { prisma, io } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { requirePermission } from "../middleware/auth";
import {
  generateCallNumber,
  sanitizeString,
  parsePagination,
  paginatedResponse,
} from "../utils/helpers";
import { z } from "zod";

const router = Router();

// ============================================================
// GET /api/dispatch/calls - List calls
// ============================================================
router.get(
  "/calls",
  asyncHandler(async (req: Request, res: Response) => {
    const { page, limit, skip } = parsePagination(req.query as any);
    const status = req.query.status as string | undefined;
    const priority = req.query.priority as string | undefined;
    const departmentId = req.query.departmentId as string | undefined;

    const where: any = {};
    if (status) where.status = status;
    if (priority) where.priority = priority;
    if (departmentId) where.departmentId = departmentId;

    const [calls, total] = await Promise.all([
      prisma.dispatchCall.findMany({
        where,
        include: {
          department: { select: { id: true, name: true, code: true } },
          creator: {
            select: {
              id: true, firstName: true, lastName: true,
              badgeNumber: true, callsign: true,
            },
          },
          handler: {
            select: {
              id: true, firstName: true, lastName: true,
              badgeNumber: true, callsign: true,
            },
          },
          assignments: {
            include: {
              officer: {
                select: {
                  id: true, firstName: true, lastName: true,
                  badgeNumber: true, callsign: true,
                },
              },
            },
          },
          notes: { orderBy: { createdAt: "desc" }, take: 5 },
        },
        skip,
        take: limit,
        orderBy: [
          { priority: "asc" },
          { createdAt: "desc" },
        ],
      }),
      prisma.dispatchCall.count({ where }),
    ]);

    res.json(paginatedResponse(calls, total, page, limit));
  })
);

// ============================================================
// GET /api/dispatch/calls/active - Active calls only
// ============================================================
router.get(
  "/calls/active",
  asyncHandler(async (_req: Request, res: Response) => {
    const calls = await prisma.dispatchCall.findMany({
      where: {
        status: { notIn: ["COMPLETED", "CANCELLED"] },
      },
      include: {
        department: { select: { id: true, name: true, code: true } },
        creator: {
          select: {
            id: true, firstName: true, lastName: true, callsign: true,
          },
        },
        assignments: {
          include: {
            officer: {
              select: {
                id: true, firstName: true, lastName: true, callsign: true,
              },
            },
          },
        },
      },
      orderBy: [{ priority: "asc" }, { createdAt: "desc" }],
    });

    res.json(calls);
  })
);

// ============================================================
// GET /api/dispatch/calls/:id
// ============================================================
router.get(
  "/calls/:id",
  asyncHandler(async (req: Request, res: Response) => {
    const call = await prisma.dispatchCall.findUnique({
      where: { id: req.params.id },
      include: {
        department: true,
        creator: {
          select: {
            id: true, firstName: true, lastName: true,
            badgeNumber: true, callsign: true,
          },
        },
        handler: {
          select: {
            id: true, firstName: true, lastName: true,
            badgeNumber: true, callsign: true,
          },
        },
        assignments: {
          include: {
            officer: {
              select: {
                id: true, firstName: true, lastName: true,
                badgeNumber: true, callsign: true, status: true,
              },
            },
          },
        },
        notes: { orderBy: { createdAt: "desc" } },
      },
    });

    if (!call) throw createError(404, "Call not found.");
    res.json(call);
  })
);

// ============================================================
// POST /api/dispatch/calls - Create call
// ============================================================
const createCallSchema = z.object({
  type: z.string().min(1).max(64),
  description: z.string().min(1).max(5000),
  location: z.string().min(1).max(255),
  lat: z.number().optional(),
  lng: z.number().optional(),
  priority: z.enum(["PRIORITY_1", "PRIORITY_2", "PRIORITY_3", "PRIORITY_4"]),
  departmentId: z.string().uuid(),
});

router.post(
  "/calls",
  requirePermission("dispatch", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = createCallSchema.parse(req.body);

    const call = await prisma.dispatchCall.create({
      data: {
        callNumber: generateCallNumber(),
        type: sanitizeString(body.type),
        description: sanitizeString(body.description),
        location: sanitizeString(body.location),
        lat: body.lat,
        lng: body.lng,
        priority: body.priority as any,
        departmentId: body.departmentId,
        creatorId: req.user!.officerId!,
        status: "PENDING",
      },
      include: {
        department: { select: { id: true, name: true, code: true } },
        creator: {
          select: {
            id: true, firstName: true, lastName: true, callsign: true,
          },
        },
      },
    });

    // Broadcast new call to dispatch
    io.to("dispatch").emit("dispatch:call:new", call);
    io.to("notifications").emit("notification:new", {
      type: "NEW_CALL",
      title: `New ${body.priority.replace("_", " ")} Call`,
      message: `${body.type} at ${body.location}`,
      priority: body.priority === "PRIORITY_1" ? "URGENT" : "HIGH",
      data: call,
    });

    res.status(201).json(call);
  })
);

// ============================================================
// PATCH /api/dispatch/calls/:id - Update call
// ============================================================
const updateCallSchema = z.object({
  type: z.string().min(1).max(64).optional(),
  description: z.string().min(1).max(5000).optional(),
  location: z.string().min(1).max(255).optional(),
  lat: z.number().optional(),
  lng: z.number().optional(),
  priority: z.enum(["PRIORITY_1", "PRIORITY_2", "PRIORITY_3", "PRIORITY_4"]).optional(),
  status: z.enum(["PENDING", "ASSIGNED", "EN_ROUTE", "ON_SCENE", "COMPLETED", "CANCELLED"]).optional(),
  handlerId: z.string().uuid().optional(),
});

router.patch(
  "/calls/:id",
  requirePermission("dispatch", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = updateCallSchema.parse(req.body);

    const updateData: any = { ...body };
    if (body.type) updateData.type = sanitizeString(body.type);
    if (body.description) updateData.description = sanitizeString(body.description);
    if (body.location) updateData.location = sanitizeString(body.location);

    if (body.status === "COMPLETED" || body.status === "CANCELLED") {
      updateData.completedAt = new Date();
    }

    const call = await prisma.dispatchCall.update({
      where: { id: req.params.id },
      data: updateData,
      include: {
        department: { select: { id: true, name: true, code: true } },
        assignments: {
          include: {
            officer: {
              select: {
                id: true, firstName: true, lastName: true, callsign: true,
              },
            },
          },
        },
      },
    });

    // Broadcast update
    io.to("dispatch").emit("dispatch:call:update", call);

    res.json(call);
  })
);

// ============================================================
// POST /api/dispatch/calls/:id/assign - Assign officer to call
// ============================================================
const assignSchema = z.object({
  officerId: z.string().uuid(),
});

router.post(
  "/calls/:id/assign",
  requirePermission("dispatch", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const body = assignSchema.parse(req.body);

    // Check call exists
    const call = await prisma.dispatchCall.findUnique({
      where: { id: req.params.id },
    });
    if (!call) throw createError(404, "Call not found.");

    // Check officer exists
    const officer = await prisma.officer.findUnique({
      where: { id: body.officerId },
    });
    if (!officer) throw createError(404, "Officer not found.");

    // Create assignment
    const assignment = await prisma.callAssignment.create({
      data: {
        callId: call.id,
        officerId: body.officerId,
      },
      include: {
        officer: {
          select: {
            id: true, firstName: true, lastName: true, callsign: true,
          },
        },
      },
    });

    // Update call status if needed
    if (call.status === "PENDING") {
      await prisma.dispatchCall.update({
        where: { id: call.id },
        data: { status: "ASSIGNED", handlerId: body.officerId },
      });
    }

    // Update officer status
    await prisma.officer.update({
      where: { id: body.officerId },
      data: { status: "EN_ROUTE" },
    });
    await prisma.unit.updateMany({
      where: { officerId: body.officerId, offDutyAt: null },
      data: { status: "EN_ROUTE" },
    });

    // Notify the officer
    io.to(`officer:${body.officerId}`).emit("dispatch:assigned", {
      callId: call.id,
      callNumber: call.callNumber,
      type: call.type,
      location: call.location,
      priority: call.priority,
    });

    io.to("dispatch").emit("dispatch:call:update", {
      ...call,
      status: call.status === "PENDING" ? "ASSIGNED" : call.status,
    });

    res.json(assignment);
  })
);

// ============================================================
// POST /api/dispatch/calls/:id/unassign - Remove officer from call
// ============================================================
router.post(
  "/calls/:id/unassign",
  requirePermission("dispatch", "admin"),
  asyncHandler(async (req: Request, res: Response) => {
    const { officerId } = req.body;
    if (!officerId) throw createError(400, "officerId required.");

    await prisma.callAssignment.updateMany({
      where: {
        callId: req.params.id,
        officerId,
        clearedAt: null,
      },
      data: { clearedAt: new Date() },
    });

    io.to("dispatch").emit("dispatch:call:update", { id: req.params.id });

    res.json({ message: "Officer unassigned." });
  })
);

// ============================================================
// POST /api/dispatch/calls/:id/notes - Add note
// ============================================================
const addNoteSchema = z.object({
  content: z.string().min(1).max(5000),
});

router.post(
  "/calls/:id/notes",
  asyncHandler(async (req: Request, res: Response) => {
    const body = addNoteSchema.parse(req.body);

    const note = await prisma.callNote.create({
      data: {
        callId: req.params.id,
        content: sanitizeString(body.content),
        createdBy: req.user!.username,
      },
    });

    io.to("dispatch").emit("dispatch:call:note", {
      callId: req.params.id,
      note,
    });

    res.status(201).json(note);
  })
);

export { router as dispatchRoutes };
