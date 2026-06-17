import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
  console.log("Seeding database...");

  // ============================================================
  // Permissions
  // ============================================================
  const permissionData = [
    { name: "admin", description: "Full system administration" },
    { name: "dispatch", description: "Dispatch operations" },
    { name: "manage_officers", description: "Manage officer profiles" },
    { name: "manage_departments", description: "Manage departments and ranks" },
    { name: "manage_users", description: "Manage user accounts" },
    { name: "supervisor", description: "Supervisor functions (approvals, reviews)" },
    { name: "view_reports", description: "View reports" },
    { name: "create_reports", description: "Create and edit reports" },
    { name: "approve_reports", description: "Approve reports" },
    { name: "manage_evidence", description: "Manage evidence" },
    { name: "manage_bolos", description: "Create and manage BOLOs" },
    { name: "manage_warrants", description: "Manage warrants" },
    { name: "view_civilian_db", description: "View civilian database" },
    { name: "edit_civilian_db", description: "Edit civilian records" },
    { name: "view_vehicle_db", description: "View vehicle database" },
    { name: "edit_vehicle_db", description: "Edit vehicle records" },
    { name: "view_criminal_records", description: "View criminal records" },
    { name: "create_criminal_records", description: "Create criminal records" },
    { name: "view_audit_logs", description: "View audit logs" },
    { name: "manage_announcements", description: "Manage announcements" },
  ];

  const permissions: Record<string, string> = {};
  for (const perm of permissionData) {
    const created = await prisma.permission.upsert({
      where: { name: perm.name },
      update: { description: perm.description },
      create: perm,
    });
    permissions[created.name] = created.id;
  }
  console.log(`  Created ${permissionData.length} permissions`);

  // ============================================================
  // Roles
  // ============================================================
  const roleData = [
    { name: "Administrator", description: "Full system access", level: 100 },
    { name: "Chief", description: "Department chief", level: 90 },
    { name: "Captain", description: "Captain", level: 80 },
    { name: "Lieutenant", description: "Lieutenant", level: 70 },
    { name: "Sergeant", description: "Sergeant", level: 60 },
    { name: "Corporal", description: "Corporal", level: 50 },
    { name: "Senior Officer", description: "Senior Officer", level: 40 },
    { name: "Officer", description: "Regular officer", level: 30 },
    { name: "Recruit", description: "Recruit / Probationary", level: 20 },
    { name: "Dispatcher", description: "Dispatch operator", level: 10 },
    { name: "Civilian", description: "Civilian role", level: 0 },
  ];

  const roles: Record<string, string> = {};
  for (const role of roleData) {
    const created = await prisma.role.upsert({
      where: { name: role.name },
      update: { level: role.level },
      create: role,
    });
    roles[created.name] = created.id;
  }
  console.log(`  Created ${roleData.length} roles`);

  // Assign permissions to roles
  const adminPerms = Object.values(permissions);
  const adminRoleId = roles["Administrator"];
  for (const permId of adminPerms) {
    await prisma.rolePermission.upsert({
      where: { roleId_permissionId: { roleId: adminRoleId, permissionId: permId } },
      update: {},
      create: { roleId: adminRoleId, permissionId: permId },
    });
  }

  // Supervisor permissions
  const supervisorPerms = ["supervisor", "approve_reports", "view_reports", "create_reports", "view_civilian_db", "view_vehicle_db", "view_criminal_records", "manage_bolos"];
  for (const permName of supervisorPerms) {
    if (permissions[permName]) {
      await prisma.rolePermission.upsert({
        where: { roleId_permissionId: { roleId: roles["Sergeant"], permissionId: permissions[permName] } },
        update: {},
        create: { roleId: roles["Sergeant"], permissionId: permissions[permName] },
      });
    }
  }

  // Dispatcher permissions
  const dispatcherPerms = ["dispatch", "view_civilian_db", "view_vehicle_db"];
  for (const permName of dispatcherPerms) {
    if (permissions[permName]) {
      await prisma.rolePermission.upsert({
        where: { roleId_permissionId: { roleId: roles["Dispatcher"], permissionId: permissions[permName] } },
        update: {},
        create: { roleId: roles["Dispatcher"], permissionId: permissions[permName] },
      });
    }
  }
  // Assign permissions to each role based on level thresholds
  const levelPermMap: { minLevel: number; perms: string[] }[] = [
    { minLevel: 90, perms: ["dispatch", "manage_officers", "manage_departments", "manage_users", "supervisor", "view_reports", "create_reports", "approve_reports", "manage_evidence", "manage_bolos", "manage_warrants", "view_civilian_db", "edit_civilian_db", "view_vehicle_db", "edit_vehicle_db", "view_criminal_records", "create_criminal_records", "view_audit_logs", "manage_announcements"] },
    { minLevel: 80, perms: ["dispatch", "manage_officers", "manage_departments", "supervisor", "view_reports", "create_reports", "approve_reports", "manage_evidence", "manage_bolos", "manage_warrants", "view_civilian_db", "edit_civilian_db", "view_vehicle_db", "edit_vehicle_db", "view_criminal_records", "create_criminal_records", "view_audit_logs", "manage_announcements"] },
    { minLevel: 70, perms: ["dispatch", "manage_officers", "supervisor", "view_reports", "create_reports", "approve_reports", "manage_evidence", "manage_bolos", "manage_warrants", "view_civilian_db", "edit_civilian_db", "view_vehicle_db", "edit_vehicle_db", "view_criminal_records", "create_criminal_records"] },
    { minLevel: 60, perms: ["dispatch", "supervisor", "view_reports", "create_reports", "approve_reports", "manage_evidence", "manage_bolos", "view_civilian_db", "view_vehicle_db", "view_criminal_records", "create_criminal_records"] },
    { minLevel: 50, perms: ["dispatch", "view_reports", "create_reports", "manage_evidence", "manage_bolos", "view_civilian_db", "view_vehicle_db", "view_criminal_records", "create_criminal_records"] },
    { minLevel: 40, perms: ["view_reports", "create_reports", "manage_evidence", "manage_bolos", "view_civilian_db", "view_vehicle_db", "view_criminal_records", "create_criminal_records"] },
    { minLevel: 30, perms: ["view_reports", "create_reports", "view_civilian_db", "view_vehicle_db", "view_criminal_records"] },
    { minLevel: 20, perms: ["view_reports", "create_reports", "view_civilian_db", "view_vehicle_db"] },
    { minLevel: 10, perms: ["view_reports", "create_reports", "view_civilian_db", "view_vehicle_db", "view_criminal_records"] },
  ];

  for (const role of roleData) {
    const roleId = roles[role.name];
    if (!roleId) continue;
    // Find the highest threshold this role meets
    const tier = levelPermMap.find(t => role.level >= t.minLevel);
    if (!tier) continue;
    for (const permName of tier.perms) {
      if (!permissions[permName]) continue;
      await prisma.rolePermission.upsert({
        where: { roleId_permissionId: { roleId, permissionId: permissions[permName] } },
        update: {},
        create: { roleId, permissionId: permissions[permName] },
      });
    }
  }

  console.log("  Assigned role permissions");

  // ============================================================
  // Departments
  // ============================================================
  const deptData = [
    { name: "Los Santos Police Department", code: "LSPD", color: "#1E40AF" },
    { name: "Blaine County Sheriff's Office", code: "BCSO", color: "#7C3AED" },
    { name: "San Andreas Highway Patrol", code: "SAHP", color: "#B45309" },
    { name: "Los Santos Fire Department", code: "LSFD", color: "#DC2626" },
    { name: "Dispatch Center", code: "DISP", color: "#059669" },
  ];

  const departments: Record<string, string> = {};
  for (const dept of deptData) {
    const created = await prisma.department.upsert({
      where: { code: dept.code },
      update: { name: dept.name, color: dept.color },
      create: dept,
    });
    departments[created.code] = created.id;
  }
  console.log(`  Created ${deptData.length} departments`);

  // ============================================================
  // Ranks (for LSPD as example)
  // ============================================================
  const lspdRanks = [
    { name: "Chief of Police", level: 100, badgePrefix: "C" },
    { name: "Deputy Chief", level: 95, badgePrefix: "DC" },
    { name: "Commander", level: 90, badgePrefix: "CMD" },
    { name: "Captain", level: 80, badgePrefix: "CPT" },
    { name: "Lieutenant", level: 70, badgePrefix: "LT" },
    { name: "Sergeant", level: 60, badgePrefix: "SGT" },
    { name: "Corporal", level: 50, badgePrefix: "CPL" },
    { name: "Senior Officer", level: 40, badgePrefix: "SO" },
    { name: "Officer", level: 30, badgePrefix: "OFC" },
    { name: "Probationary Officer", level: 20, badgePrefix: "PO" },
    { name: "Cadet", level: 10, badgePrefix: "CDT" },
  ];

  const bcsoRanks = [
    { name: "Sheriff", level: 100, badgePrefix: "S" },
    { name: "Undersheriff", level: 95, badgePrefix: "US" },
    { name: "Chief Deputy", level: 90, badgePrefix: "CD" },
    { name: "Captain", level: 80, badgePrefix: "CPT" },
    { name: "Lieutenant", level: 70, badgePrefix: "LT" },
    { name: "Sergeant", level: 60, badgePrefix: "SGT" },
    { name: "Corporal", level: 50, badgePrefix: "CPL" },
    { name: "Senior Deputy", level: 40, badgePrefix: "SD" },
    { name: "Deputy", level: 30, badgePrefix: "DEP" },
    { name: "Probationary Deputy", level: 20, badgePrefix: "PD" },
    { name: "Cadet", level: 10, badgePrefix: "CDT" },
  ];

  const sahpRanks = [
    { name: "Commissioner", level: 100, badgePrefix: "COM" },
    { name: "Deputy Commissioner", level: 95, badgePrefix: "DCOM" },
    { name: "Major", level: 90, badgePrefix: "MAJ" },
    { name: "Captain", level: 80, badgePrefix: "CPT" },
    { name: "Lieutenant", level: 70, badgePrefix: "LT" },
    { name: "Sergeant", level: 60, badgePrefix: "SGT" },
    { name: "Corporal", level: 50, badgePrefix: "CPL" },
    { name: "Senior Trooper", level: 40, badgePrefix: "ST" },
    { name: "Trooper", level: 30, badgePrefix: "T" },
    { name: "Probationary Trooper", level: 20, badgePrefix: "PT" },
    { name: "Cadet", level: 10, badgePrefix: "CDT" },
  ];

  for (const [deptCode, ranks] of Object.entries({ LSPD: lspdRanks, BCSO: bcsoRanks, SAHP: sahpRanks })) {
    for (const rank of ranks) {
      await prisma.rank.upsert({
        where: { name_departmentId: { name: rank.name, departmentId: departments[deptCode] } },
        update: { level: rank.level, badgePrefix: rank.badgePrefix },
        create: {
          name: rank.name,
          departmentId: departments[deptCode],
          level: rank.level,
          badgePrefix: rank.badgePrefix,
        },
      });
    }
  }
  console.log("  Created ranks for all departments");

  // ============================================================
  // Admin User
  // ============================================================
  const adminPassword = await bcrypt.hash("admin123", 12);
  const adminUser = await prisma.user.upsert({
    where: { username: "admin" },
    update: {},
    create: {
      username: "admin",
      passwordHash: adminPassword,
      email: "admin@cad.local",
    },
  });

  // Grant admin all permissions
  for (const permId of Object.values(permissions)) {
    await prisma.userPermission.upsert({
      where: { userId_permissionId: { userId: adminUser.id, permissionId: permId } },
      update: {},
      create: { userId: adminUser.id, permissionId: permId, granted: true, grantedBy: adminUser.id },
    });
  }

  // Create admin officer profile
  const adminOfficer = await prisma.officer.upsert({
    where: { userId: adminUser.id },
    update: {},
    create: {
      userId: adminUser.id,
      firstName: "System",
      lastName: "Administrator",
      badgeNumber: "ADMIN",
      departmentId: departments["LSPD"],
      rankId: (await prisma.rank.findFirst({
        where: { name: "Chief of Police", departmentId: departments["LSPD"] },
      }))!.id,
      roleId: roles["Administrator"],
    },
  });
  console.log("  Created admin user (username: admin, password: admin123)");

  // ============================================================
  // Sample Dispatcher User
  // ============================================================
  const dispatcherPassword = await bcrypt.hash("dispatch123", 12);
  const dispatcherUser = await prisma.user.upsert({
    where: { username: "dispatcher" },
    update: {},
    create: {
      username: "dispatcher",
      passwordHash: dispatcherPassword,
      email: "dispatch@cad.local",
    },
  });

  // Grant dispatch permissions
  const dispatchPermIds = ["dispatch", "view_civilian_db", "view_vehicle_db"].map(
    (name) => permissions[name]
  ).filter(Boolean);
  for (const permId of dispatchPermIds) {
    await prisma.userPermission.upsert({
      where: { userId_permissionId: { userId: dispatcherUser.id, permissionId: permId } },
      update: {},
      create: { userId: dispatcherUser.id, permissionId: permId, granted: true, grantedBy: adminUser.id },
    });
  }
  console.log("  Created dispatcher user (username: dispatcher, password: dispatch123)");

  // ============================================================
  // Sample Announcement
  // ============================================================
  await prisma.announcement.create({
    data: {
      title: "Welcome to the CAD/MDT System",
      content: "The Police CAD/MDT system is now online. Please report any issues to the administration team.",
      priority: "NORMAL",
      createdBy: "admin",
    },
  });
  console.log("  Created welcome announcement");

  console.log("\nDatabase seeded successfully!");
  console.log("\nDefault accounts:");
  console.log("  Admin:      username=admin      password=admin123");
  console.log("  Dispatcher: username=dispatcher  password=dispatch123");
  console.log("\nIMPORTANT: Change these passwords before production use!");
}

main()
  .catch((e) => {
    console.error("Seed failed:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
