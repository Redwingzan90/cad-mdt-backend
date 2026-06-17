-- Police CAD/MDT System - Schema Reference
-- This file provides a readable reference of the database schema.
-- For actual migrations, use Prisma: npx prisma db push

-- The complete schema is defined in schema.prisma and includes:

-- USERS & AUTH
--   users, sessions, permissions, roles, user_permissions, role_permissions

-- DEPARTMENTS & RANKS
--   departments, ranks

-- OFFICERS
--   officers, certifications, training_records, officer_notes,
--   disciplinary_records, equipment, units

-- DISPATCH
--   dispatch_calls, call_assignments, call_notes, call_units

-- 911
--   emergency_calls

-- CIVILIAN DATABASE
--   civilians, licenses

-- VEHICLES
--   vehicles

-- CRIMINAL RECORDS
--   arrest_reports, citations, warnings, warrants

-- REPORTS
--   incident_reports, crash_reports, crash_vehicles,
--   use_of_force_reports, investigation_reports

-- BOLO SYSTEM
--   bolos

-- EVIDENCE
--   evidence

-- NOTIFICATIONS
--   notifications

-- AUDIT
--   audit_logs, announcements

-- All tables use UUID primary keys, proper indexes,
-- foreign keys with cascade deletes, and timestamps.
