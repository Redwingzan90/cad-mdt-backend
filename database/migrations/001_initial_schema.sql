-- Police CAD/MDT System - Database Migration
-- Migration 001: Initial Schema
-- Run: npx prisma db push OR npx prisma migrate dev

-- This migration is handled by Prisma ORM.
-- Run the following commands to set up the database:

-- 1. Create the database:
--    CREATE DATABASE cad_mdt CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 2. Set DATABASE_URL in backend/.env:
--    DATABASE_URL="mysql://root:password@localhost:3306/cad_mdt"

-- 3. Push the schema:
--    cd backend && npx prisma db push

-- 4. Seed the database:
--    cd backend && npx tsx prisma/seed.ts

-- The schema.prisma file contains all table definitions with:
-- - Proper indexes for performance
-- - Foreign key constraints
-- - Cascade deletes where appropriate
-- - Unique constraints to prevent duplicates
-- - Enum types for data integrity
