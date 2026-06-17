import { Server as SocketServer, Socket } from "socket.io";
import jwt from "jsonwebtoken";
import { prisma } from "./index";
import { logger } from "./utils/logger";
import type { AuthUser } from "./middleware/auth";

// Extend Socket with auth user
interface AuthSocket extends Socket {
  user?: AuthUser;
}

// Connected users map
const connectedUsers = new Map<string, AuthSocket>();

export function initializeSocket(io: SocketServer) {
  // ============================================================
  // Authentication Middleware
  // ============================================================
  io.use(async (socket: AuthSocket, next) => {
    try {
      const token =
        socket.handshake.auth.token ||
        socket.handshake.headers.authorization?.replace("Bearer ", "");

      if (!token) {
        return next(new Error("Authentication required"));
      }

      const secret = process.env.JWT_SECRET;
      if (!secret) return next(new Error("Server misconfiguration"));

      const decoded = jwt.verify(token, secret) as {
        id: string;
        username: string;
      };

      const user = await prisma.user.findUnique({
        where: { id: decoded.id },
        include: {
          permissions: { include: { permission: true } },
          officer: { select: { id: true } },
        },
      });

      if (!user || !user.active) {
        return next(new Error("User not found or inactive"));
      }

      const permissions = user.permissions
        .filter((p) => p.granted)
        .map((p) => p.permission.name);

      socket.user = {
        id: user.id,
        username: user.username,
        officerId: user.officer?.id,
        permissions,
      };

      next();
    } catch (err) {
      next(new Error("Invalid token"));
    }
  });

  // ============================================================
  // Connection Handler
  // ============================================================
  io.on("connection", (socket: AuthSocket) => {
    if (!socket.user) return;

    const userId = socket.user.id;
    connectedUsers.set(userId, socket);
    logger.info(`Socket connected: ${socket.user.username} (${userId})`);

    // Join user-specific room
    socket.join(`user:${userId}`);
    // Join officer room if applicable
    if (socket.user.officerId) {
      socket.join(`officer:${socket.user.officerId}`);
    }
    // Join department rooms
    socket.join("dispatch");
    socket.join("notifications");

    // ============================================================
    // Dispatch Events
    // ============================================================
    socket.on("dispatch:join", () => {
      socket.join("dispatch");
    });

    socket.on("dispatch:leave", () => {
      socket.leave("dispatch");
    });

    // ============================================================
    // Unit Location Updates
    // ============================================================
    socket.on("unit:location", async (data: { lat: number; lng: number }) => {
      if (!socket.user?.officerId) return;

      try {
        await prisma.unit.update({
          where: { officerId: socket.user.officerId },
          data: {
            lastLat: data.lat,
            lastLng: data.lng,
            lastUpdate: new Date(),
          },
        });

        // Broadcast to dispatch
        io.to("dispatch").emit("unit:location:update", {
          officerId: socket.user.officerId,
          lat: data.lat,
          lng: data.lng,
          timestamp: new Date(),
        });
      } catch {
        // Officer may not have an active unit
      }
    });

    // ============================================================
    // Status Updates
    // ============================================================
    socket.on(
      "unit:status",
      async (data: { status: string; detail?: string }) => {
        if (!socket.user?.officerId) return;

        try {
          await prisma.unit.update({
            where: { officerId: socket.user.officerId },
            data: { status: data.status as any },
          });

          io.to("dispatch").emit("unit:status:update", {
            officerId: socket.user.officerId,
            status: data.status,
            detail: data.detail,
          });
        } catch {
          // No active unit
        }
      }
    );

    // ============================================================
    // Typing Indicators (for dispatch notes)
    // ============================================================
    socket.on("dispatch:typing", (data: { callId: string }) => {
      socket.to("dispatch").emit("dispatch:typing", {
        callId: data.callId,
        userId: socket.user?.id,
        username: socket.user?.username,
      });
    });

    // ============================================================
    // Disconnect
    // ============================================================
    socket.on("disconnect", (reason) => {
      connectedUsers.delete(userId);
      logger.info(`Socket disconnected: ${socket.user?.username} (${reason})`);
    });

    socket.on("error", (err) => {
      logger.error(`Socket error for ${socket.user?.username}:`, err);
    });
  });

  logger.info("Socket.io initialized");
}

// ============================================================
// Helper: Emit to all connected clients
// ============================================================
export function emitToAll(io: SocketServer, event: string, data: unknown) {
  io.emit(event, data);
}

// ============================================================
// Helper: Emit to specific user
// ============================================================
export function emitToUser(
  io: SocketServer,
  userId: string,
  event: string,
  data: unknown
) {
  io.to(`user:${userId}`).emit(event, data);
}

// ============================================================
// Helper: Emit to dispatch room
// ============================================================
export function emitToDispatch(io: SocketServer, event: string, data: unknown) {
  io.to("dispatch").emit(event, data);
}

// ============================================================
// Helper: Get connected user count
// ============================================================
export function getConnectedUserCount(): number {
  return connectedUsers.size;
}
