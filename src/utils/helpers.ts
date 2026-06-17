import { v4 as uuidv4 } from "uuid";
import { z } from "zod";

/**
 * Zod string field that accepts any parseable datetime string.
 * Works with ISO 8601, datetime-local ("2024-06-16T14:30"), and other formats.
 */
export const dateTimeField = z
  .string()
  .refine((val) => !isNaN(new Date(val).getTime()), {
    message: "Invalid datetime",
  })
  .transform((val) => new Date(val).toISOString());

/**
 * Optional version of dateTimeField
 */
export const optionalDateTimeField = dateTimeField.optional();

/**
 * Generate a unique report/call number
 * Format: PREFIX-YYYYMMDD-XXXX (e.g., ARR-20260615-0001)
 */
export function generateReportNumber(prefix: string): string {
  const now = new Date();
  const date = now.toISOString().slice(0, 10).replace(/-/g, "");
  const random = Math.floor(Math.random() * 9999)
    .toString()
    .padStart(4, "0");
  return `${prefix}-${date}-${random}`;
}

/**
 * Generate a call number for dispatch
 * Format: CAD-XXXXXX
 */
export function generateCallNumber(): string {
  const random = Math.floor(Math.random() * 999999)
    .toString()
    .padStart(6, "0");
  return `CAD-${random}`;
}

/**
 * Generate a UUID
 */
export function generateUUID(): string {
  return uuidv4();
}

/**
 * Sanitize a string for safe storage
 */
export function sanitizeString(input: string): string {
  return input
    .replace(/[<>]/g, "") // Remove HTML brackets
    .trim()
    .slice(0, 10000); // Limit length
}

/**
 * Validate a plate number format
 */
export function isValidPlate(plate: string): boolean {
  return /^[A-Z0-9]{1,10}$/i.test(plate.trim());
}

/**
 * Format a date for display
 */
export function formatDate(date: Date | string): string {
  const d = typeof date === "string" ? new Date(date) : date;
  return d.toLocaleString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Check if a value is a valid UUID
 */
export function isValidUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

/**
 * Paginate query parameters
 */
export function parsePagination(query: { page?: string; limit?: string }) {
  const page = Math.max(1, parseInt(query.page || "1", 10));
  const limit = Math.min(100, Math.max(1, parseInt(query.limit || "25", 10)));
  const skip = (page - 1) * limit;
  return { page, limit, skip };
}

/**
 * Build pagination response
 */
export function paginatedResponse<T>(data: T[], total: number, page: number, limit: number) {
  return {
    data,
    pagination: {
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    },
  };
}

/**
 * Resolve all permissions for a user by merging:
 * 1. Direct UserPermission entries
 * 2. RolePermission entries from the officer's roleId
 * 3. If no roleId, find the role matching the officer's rank level
 */
export async function resolveUserPermissions(
  userId: string
): Promise<string[]> {
  // Lazy import to avoid circular dependency
  const { prisma } = await import("../index");
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      permissions: {
        include: { permission: { select: { name: true } } },
      },
      officer: {
        select: { id: true, roleId: true, rankId: true },
      },
    },
  });

  if (!user) return [];

  // 1. Direct user permissions
  const userPerms = user.permissions
    .filter((p: any) => p.granted)
    .map((p: any) => p.permission.name);

  // 2. Role-based permissions
  let roleId = user.officer?.roleId;

  // 3. Fallback: if no roleId, find the role matching the officer's rank level
  if (!roleId && user.officer?.rankId) {
    const rank = await prisma.rank.findUnique({
      where: { id: user.officer.rankId },
      select: { level: true },
    });
    if (rank) {
      const matchingRole = await prisma.role.findFirst({
        where: { level: { lte: rank.level } },
        orderBy: { level: "desc" },
        select: { id: true },
      });
      if (matchingRole) roleId = matchingRole.id;
    }
  }

  let rolePerms: string[] = [];
  if (roleId) {
    const rolePermissionRecords = await prisma.rolePermission.findMany({
      where: { roleId },
      include: { permission: { select: { name: true } } },
    });
    rolePerms = rolePermissionRecords.map((rp: any) => rp.permission.name);
  }

  return Array.from(new Set([...userPerms, ...rolePerms]));
}
