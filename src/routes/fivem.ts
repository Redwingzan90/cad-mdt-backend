import { Router, Request, Response, NextFunction } from "express";
import { prisma, io } from "../index";
import { asyncHandler } from "./base";
import { createError } from "../middleware/errorHandler";
import { sanitizeString } from "../utils/helpers";

const router = Router();

// ============================================================
// IP Restriction Middleware for FiveM
// ============================================================
function fivemAuth(req: Request, _res: Response, next: NextFunction) {
  const serverKey = req.headers["x-server-key"] as string;
  const expectedKey = process.env.FIVEM_SERVER_KEY;

  if (!expectedKey) {
    return next(createError(500, "FiveM server key not configured."));
  }

  if (serverKey !== expectedKey) {
    return next(createError(403, "Invalid server key."));
  }

  next();
}

router.use(fivemAuth);

// ============================================================
// POST /api/fivem/player-duty - Player goes on/off duty
// ============================================================
router.post(
  "/player-duty",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier, onDuty, callsign, departmentCode } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    const identifier = String(rawIdentifier);

    // Find officer by game identifier (stored in user.discordId or custom field)
    const user = await prisma.user.findFirst({
      where: {
        OR: [
          { discordId: identifier },
          { username: identifier },
        ],
      },
      include: { officer: true },
    });

    if (!user?.officer) {
      return res.json({ success: false, message: "No officer found for this player." });
    }

    if (onDuty && callsign) {
      const dept = departmentCode
        ? await prisma.department.findUnique({ where: { code: departmentCode } })
        : null;

      const departmentId = dept?.id || user.officer.departmentId;

      // Go on duty
      await prisma.officer.update({
        where: { id: user.officer.id },
        data: { status: "AVAILABLE", callsign },
      });

      // Create or update unit
      await prisma.unit.upsert({
        where: { officerId: user.officer.id },
        update: {
          callsign,
          departmentId,
          status: "AVAILABLE",
          offDutyAt: null,
          onDutyAt: new Date(),
        },
        create: {
          officerId: user.officer.id,
          callsign,
          departmentId,
          status: "AVAILABLE",
        },
      });

      io.to("dispatch").emit("unit:status:update", {
        officerId: user.officer.id,
        status: "AVAILABLE",
        callsign,
      });
    } else {
      // Go off duty
      await prisma.officer.update({
        where: { id: user.officer.id },
        data: { status: "OFF_DUTY" },
      });

      await prisma.unit.updateMany({
        where: { officerId: user.officer.id, offDutyAt: null },
        data: { offDutyAt: new Date(), status: "OUT_OF_SERVICE" },
      });

      io.to("dispatch").emit("unit:status:update", {
        officerId: user.officer.id,
        status: "OFF_DUTY",
      });
    }

    res.json({ success: true });
  })
);

// ============================================================
// POST /api/fivem/plate-check - Vehicle plate lookup
// ============================================================
router.post(
  "/plate-check",
  asyncHandler(async (req: Request, res: Response) => {
    const { plate } = req.body;
    if (!plate) throw createError(400, "Plate number required.");

    const vehicle = await prisma.vehicle.findUnique({
      where: { plate: plate.toUpperCase() },
      include: {
        owner: {
          include: {
            licenses: { where: { type: "drivers" } },
            warrants: { where: { status: "ACTIVE" } },
          },
        },
      },
    });

    if (!vehicle) {
      return res.json({ found: false, message: "Vehicle not registered." });
    }

    const flags: string[] = [];
    if (vehicle.stolen) flags.push("STOLEN");
    if (vehicle.owner.warrants.length > 0) flags.push("OWNER HAS WARRANTS");
    if (vehicle.registrationStatus !== "VALID") flags.push("REG " + vehicle.registrationStatus);

    res.json({
      found: true,
      plate: vehicle.plate,
      model: vehicle.model,
      color: vehicle.color,
      year: vehicle.year,
      registration: vehicle.registrationStatus,
      insurance: vehicle.insuranceStatus,
      stolen: vehicle.stolen,
      owner: `${vehicle.owner.firstName} ${vehicle.owner.lastName}`,
      ownerDOB: vehicle.owner.dateOfBirth,
      licenses: vehicle.owner.licenses,
      flags,
    });
  })
);

// ============================================================
// POST /api/fivem/911 - Submit 911 call from in-game
// ============================================================
router.post(
  "/911",
  asyncHandler(async (req: Request, res: Response) => {
    const { callerName, callerPhone, description, location, lat, lng, type } = req.body;

    const call = await prisma.emergencyCall.create({
      data: {
        callerName: sanitizeString(callerName || "Unknown"),
        callerPhone,
        description: sanitizeString(description),
        location: sanitizeString(location || "Unknown"),
        lat,
        lng,
        type: sanitizeString(type || "Emergency"),
        status: "PENDING",
      },
    });

    io.to("dispatch").emit("emergency:new", call);
    io.to("notifications").emit("notification:new", {
      type: "NEW_CALL",
      title: "911 Call",
      message: `${description.slice(0, 100)}`,
      priority: "URGENT",
    });

    res.json({ success: true, callId: call.id });
  })
);

// ============================================================
// POST /api/fivem/location - Update officer location
// ============================================================
// ============================================================
// POST /api/fivem/status - Update officer status from in-game
// ============================================================
router.post(
  "/status",
  asyncHandler(async (req: Request, res: Response) => {
    const { officerId, status, detail } = req.body;
    if (!officerId || !status) throw createError(400, "officerId and status required.");

    await prisma.officer.update({
      where: { id: officerId },
      data: {
        status: status as any,
        statusDetail: detail || null,
      },
    });

    await prisma.unit.updateMany({
      where: { officerId, offDutyAt: null },
      data: { status: status as any },
    });

    io.to("dispatch").emit("unit:status:update", {
      officerId,
      status,
      detail,
    });

    res.json({ success: true });
  })
);

// ============================================================
// POST /api/fivem/location - Update officer location
// ============================================================
router.post(
  "/location",
  asyncHandler(async (req: Request, res: Response) => {
    const { officerId, lat, lng } = req.body;

    await prisma.unit.updateMany({
      where: { officerId, offDutyAt: null },
      data: { lastLat: lat, lastLng: lng, lastUpdate: new Date() },
    });

    io.to("dispatch").emit("unit:location:update", {
      officerId,
      lat,
      lng,
      timestamp: new Date(),
    });

    res.json({ success: true });
  })
);

// ============================================================
// POST /api/fivem/character-info - Get character info
// ============================================================
router.post(
  "/character-info",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier } = req.body;
    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    const identifier = String(rawIdentifier);

    const user = await prisma.user.findFirst({
      where: {
        OR: [
          { discordId: identifier },
          { username: identifier },
        ],
      },
      include: {
        officer: {
          include: {
            department: true,
            rank: true,
          },
        },
      },
    });

    if (!user) {
      return res.json({ found: false });
    }

    res.json({
      found: true,
      userId: user.id,
      officer: user.officer || null,
    });
  })
);

// ============================================================
// POST /api/fivem/gunfire - Report gunfire detection
// ============================================================
router.post(
  "/gunfire",
  asyncHandler(async (req: Request, res: Response) => {
    const { lat, lng, streetName, weapon, playerId } = req.body;

    if (!lat || !lng) throw createError(400, "Location required.");

    // Create a Priority 1 dispatch call for shots fired
    const callNumber = `CAD-${Math.floor(Math.random() * 999999).toString().padStart(6, "0")}`;

    // Find the first police department for the call
    const dept = await prisma.department.findFirst({
      where: { code: "LSPD" },
      select: { id: true },
    });

    if (!dept) {
      return res.json({ success: false, message: "No department available." });
    }

    // Find a default creator (system admin officer) since this is automated
    const systemOfficer = await prisma.officer.findFirst({
      where: { badgeNumber: "ADMIN" },
      select: { id: true },
    });

    if (!systemOfficer) {
      return res.json({ success: false, message: "No system officer available." });
    }

    const call = await prisma.dispatchCall.create({
      data: {
        callNumber,
        type: "SHOTS FIRED",
        description: `Gunfire detected at ${streetName || "Unknown Location"}. Weapon: ${weapon || "Unknown"}. Automated gunshot detection report from Player #${playerId || "Unknown"}.`,
        location: streetName || "Unknown Location",
        lat,
        lng,
        priority: "PRIORITY_1",
        departmentId: dept.id,
        creatorId: systemOfficer.id,
        status: "PENDING",
      },
      include: {
        department: { select: { id: true, name: true, code: true } },
      },
    });

    // Broadcast to dispatch and all officers
    io.to("dispatch").emit("dispatch:call:new", call);
    io.to("notifications").emit("notification:new", {
      type: "NEW_CALL",
      title: "🔫 SHOTS FIRED",
      message: `Gunfire detected at ${streetName || "Unknown"}. Priority 1 response needed.`,
      priority: "URGENT",
      data: call,
    });

    // Create a 911 emergency call record too
    await prisma.emergencyCall.create({
      data: {
        callerName: "ShotSpotter System",
        description: `Automated gunfire detection at ${streetName || "Unknown"}. Weapon: ${weapon || "Unknown"}.`,
        location: streetName || "Unknown Location",
        lat,
        lng,
        type: "Gunfire Detection",
        status: "DISPATCHED",
      },
    });

    res.json({ success: true, callId: call.id, callNumber: call.callNumber });
  })
);

// ============================================================
// POST /api/fivem/dmv/register - Register a vehicle at DMV
// ============================================================
router.post(
  "/dmv/register",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier, plate, model, color, year, civilianId } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    if (!plate || !model) throw createError(400, "Plate and model required.");
    const identifier = String(rawIdentifier);

    // Find the active civilian for this player
    let civilian = null;

    // If a specific civilianId is provided, use that (multi-character support)
    if (civilianId) {
      civilian = await prisma.civilian.findFirst({
        where: { id: civilianId, active: true },
      });
    }

    // Otherwise find the active character for this player
    if (!civilian) {
      civilian = await prisma.civilian.findFirst({
        where: { playerIdentifier: identifier, isActive: true, active: true },
      });
    }

    // Fallback: legacy lookup by notes field
    if (!civilian) {
      civilian = await prisma.civilian.findFirst({
        where: { notes: `identifier:${identifier}` },
      });
    }

    // Fallback: try matching by user's officer name or username
    if (!civilian) {
      const user = await prisma.user.findFirst({
        where: {
          OR: [
            { discordId: identifier },
            { username: identifier },
          ],
        },
        include: {
          officer: { select: { firstName: true, lastName: true } },
        },
      });

      if (user) {
        if (user.officer) {
          civilian = await prisma.civilian.findFirst({
            where: {
              firstName: user.officer.firstName,
              lastName: user.officer.lastName,
            },
          });
        }
        if (!civilian) {
          civilian = await prisma.civilian.findFirst({
            where: { firstName: user.username },
          });
        }
      }
    }

    if (!civilian) {
      return res.json({ success: false, message: "You must register as a civilian first. Visit the City Hall ID Office." });
    }

    // Check if plate already exists
    const existingVehicle = await prisma.vehicle.findUnique({
      where: { plate: plate.toUpperCase() },
    });

    if (existingVehicle) {
      return res.json({ success: false, message: "This plate is already registered." });
    }

    // Generate a plate if not provided
    const finalPlate = plate ? plate.toUpperCase().slice(0, 8) : `VEH${Math.floor(Math.random() * 9999).toString().padStart(4, "0")}`;

    const vehicle = await prisma.vehicle.create({
      data: {
        plate: finalPlate,
        model: sanitizeString(model),
        color: color || "Unknown",
        year: year ? parseInt(year) : null,
        ownerId: civilian.id,
        registrationStatus: "VALID",
        insuranceStatus: "NONE",
      },
      include: {
        owner: {
          select: { id: true, firstName: true, lastName: true },
        },
      },
    });

    // Notify MDT clients so the Vehicles view updates in real-time
    io.to("dispatch").emit("vehicle:new", vehicle);

    res.json({ success: true, plate: vehicle.plate, vehicleId: vehicle.id, ownerName: `${civilian.firstName} ${civilian.lastName}` });
  })
);

// ============================================================
// POST /api/fivem/civilian/register - Register a new civilian character
// ============================================================
router.post(
  "/civilian/register",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier, firstName, lastName, dateOfBirth, gender, address, phone } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    if (!firstName || !lastName) throw createError(400, "First and last name required.");
    const identifier = String(rawIdentifier);

    // Check if already registered by name + DOB (prevents duplicate characters globally)
    const dob = dateOfBirth ? new Date(dateOfBirth) : new Date("2000-01-01");
    if (isNaN(dob.getTime())) {
      return res.json({ success: false, message: "Invalid date of birth provided." });
    }

    const existing = await prisma.civilian.findFirst({
      where: {
        firstName: sanitizeString(firstName),
        lastName: sanitizeString(lastName),
        dateOfBirth: dob,
      },
    });

    if (existing) {
      return res.json({ success: false, message: "A civilian with this name and DOB already exists." });
    }

    // Check how many characters this player already has
    const existingCharacters = await prisma.civilian.count({
      where: { playerIdentifier: identifier, active: true },
    });

    // Deactivate current active character (if any)
    await prisma.civilian.updateMany({
      where: { playerIdentifier: identifier, isActive: true },
      data: { isActive: false },
    });

    // Create the new character - set as active (first character or switching to new one)
    const civilian = await prisma.civilian.create({
      data: {
        firstName: sanitizeString(firstName),
        lastName: sanitizeString(lastName),
        dateOfBirth: dob,
        gender: gender || null,
        address: address ? sanitizeString(address) : null,
        phone: phone || null,
        playerIdentifier: identifier,
        isActive: true,
      },
    });

    // Generate a driver's license
    const licenseNumber = `DL${Date.now().toString().slice(-8)}${Math.floor(Math.random() * 100).toString().padStart(2, "0")}`;
    await prisma.license.create({
      data: {
        civilianId: civilian.id,
        type: "drivers",
        number: licenseNumber,
        issuedAt: new Date(),
        expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000), // 1 year
        status: "VALID",
      },
    });

    // Notify MDT clients so the Civilians view updates in real-time
    io.to("dispatch").emit("civilian:new", civilian);

    const characterNumber = existingCharacters + 1;
    res.json({
      success: true,
      civilianId: civilian.id,
      licenseNumber,
      characterNumber,
      message: `Welcome, ${firstName} ${lastName}! Your civilian ID has been created and your driver's license (${licenseNumber}) has been issued. (Character #${characterNumber})`,
    });
  })
);

// ============================================================
// POST /api/fivem/characters - List all characters for a player
// ============================================================
router.post(
  "/characters",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    const identifier = String(rawIdentifier);

    // Get all characters for this player (new system + legacy)
    const characters = await prisma.civilian.findMany({
      where: {
        active: true,
        OR: [
          { playerIdentifier: identifier },
          { notes: `identifier:${identifier}` },
        ],
      },
      include: {
        licenses: { select: { type: true, status: true, number: true } },
        vehicles: { select: { id: true, plate: true, model: true, color: true, stolen: true } },
        _count: { select: { citations: true, warnings: true, arrests: true } },
      },
      orderBy: { createdAt: "asc" },
    });

    const formatted = characters.map((c) => ({
      id: c.id,
      firstName: c.firstName,
      lastName: c.lastName,
      dateOfBirth: c.dateOfBirth,
      gender: c.gender,
      address: c.address,
      phone: c.phone,
      isActive: c.isActive,
      licenses: c.licenses,
      vehicles: c.vehicles,
      citationCount: c._count.citations,
      warningCount: c._count.warnings,
      arrestCount: c._count.arrests,
    }));

    res.json({ success: true, characters: formatted });
  })
);

// ============================================================
// POST /api/fivem/character/select - Switch active character
// ============================================================
router.post(
  "/character/select",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier, civilianId } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    if (!civilianId) throw createError(400, "Civilian ID required.");
    const identifier = String(rawIdentifier);

    // Verify the civilian belongs to this player
    const civilian = await prisma.civilian.findFirst({
      where: {
        id: civilianId,
        active: true,
        OR: [
          { playerIdentifier: identifier },
          { notes: `identifier:${identifier}` },
        ],
      },
    });

    if (!civilian) {
      return res.json({ success: false, message: "Character not found or does not belong to you." });
    }

    // Deactivate all characters for this player
    await prisma.civilian.updateMany({
      where: {
        OR: [
          { playerIdentifier: identifier },
          { notes: `identifier:${identifier}` },
        ],
      },
      data: { isActive: false, playerIdentifier: identifier },
    });

    // Activate the selected character
    await prisma.civilian.update({
      where: { id: civilianId },
      data: { isActive: true, playerIdentifier: identifier },
    });

    res.json({
      success: true,
      message: `Switched to ${civilian.firstName} ${civilian.lastName}.`,
      activeCharacter: {
        id: civilian.id,
        firstName: civilian.firstName,
        lastName: civilian.lastName,
      },
    });
  })
);

// ============================================================
// POST /api/fivem/gun-license - Issue a gun license to a civilian
// ============================================================
router.post(
  "/gun-license",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier, civilianId } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    const identifier = String(rawIdentifier);

    // Find the civilian
    let civilian = null;
    if (civilianId) {
      civilian = await prisma.civilian.findFirst({
        where: { id: civilianId, active: true },
      });
    }
    if (!civilian) {
      civilian = await prisma.civilian.findFirst({
        where: { playerIdentifier: identifier, isActive: true, active: true },
      });
    }
    if (!civilian) {
      civilian = await prisma.civilian.findFirst({
        where: { notes: `identifier:${identifier}` },
      });
    }

    if (!civilian) {
      return res.json({ success: false, message: "You must register as a civilian first. Visit the City Hall ID Office." });
    }

    // Check if already has a valid gun license
    const existingGunLicense = await prisma.license.findFirst({
      where: {
        civilianId: civilian.id,
        type: "weapon",
        status: "VALID",
      },
    });

    if (existingGunLicense) {
      return res.json({ success: false, message: "You already have a valid gun license.", licenseNumber: existingGunLicense.number });
    }

    // Check if they have a valid driver's license (prerequisite)
    const driversLicense = await prisma.license.findFirst({
      where: {
        civilianId: civilian.id,
        type: "drivers",
        status: "VALID",
      },
    });

    if (!driversLicense) {
      return res.json({ success: false, message: "You need a valid driver's license before applying for a gun license." });
    }

    // Issue the gun license
    const licenseNumber = `GL${Date.now().toString().slice(-8)}${Math.floor(Math.random() * 100).toString().padStart(2, "0")}`;
    const gunLicense = await prisma.license.create({
      data: {
        civilianId: civilian.id,
        type: "weapon",
        number: licenseNumber,
        issuedAt: new Date(),
        expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000), // 1 year
        status: "VALID",
      },
    });

    res.json({
      success: true,
      licenseNumber: gunLicense.number,
      message: `Gun license issued! License: ${gunLicense.number}. Valid for 1 year.`,
    });
  })
);

// ============================================================
// POST /api/fivem/insurance - Add insurance to a vehicle
// ============================================================
router.post(
  "/insurance",
  asyncHandler(async (req: Request, res: Response) => {
    const { identifier: rawIdentifier, plate, civilianId } = req.body;

    if (!rawIdentifier) throw createError(400, "Player identifier required.");
    if (!plate) throw createError(400, "Plate number required.");
    const identifier = String(rawIdentifier);

    // Find the civilian
    let civilian = null;
    if (civilianId) {
      civilian = await prisma.civilian.findFirst({
        where: { id: civilianId, active: true },
      });
    }
    if (!civilian) {
      civilian = await prisma.civilian.findFirst({
        where: { playerIdentifier: identifier, isActive: true, active: true },
      });
    }
    if (!civilian) {
      civilian = await prisma.civilian.findFirst({
        where: { notes: `identifier:${identifier}` },
      });
    }

    if (!civilian) {
      return res.json({ success: false, message: "You must register as a civilian first." });
    }

    // Find the vehicle
    const vehicle = await prisma.vehicle.findUnique({
      where: { plate: plate.toUpperCase() },
    });

    if (!vehicle) {
      return res.json({ success: false, message: "Vehicle not found. Register it at the DMV first." });
    }

    // Check ownership
    if (vehicle.ownerId !== civilian.id) {
      return res.json({ success: false, message: "This vehicle is not registered to you." });
    }

    // Check if already insured
    if (vehicle.insuranceStatus === "VALID") {
      return res.json({ success: false, message: "This vehicle already has valid insurance.", plate: vehicle.plate });
    }

    // Add insurance
    await prisma.vehicle.update({
      where: { id: vehicle.id },
      data: { insuranceStatus: "VALID" },
    });

    res.json({
      success: true,
      plate: vehicle.plate,
      message: `Insurance activated for ${vehicle.plate} — ${vehicle.color} ${vehicle.model}. Coverage is now VALID.`,
    });
  })
);

export { router as fivemRoutes };
