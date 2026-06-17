-- Migration 002: Multi-Character Support
-- Adds player_identifier and is_active columns to civilians table
-- Run: cd backend && npx prisma db push
-- OR:  cd backend && npx prisma migrate dev --name multi-character-support

ALTER TABLE `civilians`
  ADD COLUMN `player_identifier` VARCHAR(128) NULL AFTER `notes`,
  ADD COLUMN `is_active` BOOLEAN NOT NULL DEFAULT FALSE AFTER `player_identifier`;

-- Index for fast character lookups by player identifier
CREATE INDEX `idx_civilians_player_identifier` ON `civilians` (`player_identifier`);

-- Migrate existing legacy data: copy identifier from notes field to player_identifier
-- and mark them as active (since they were the only character before)
UPDATE `civilians`
SET `player_identifier` = SUBSTRING(`notes`, 12),
    `is_active` = TRUE
WHERE `notes` LIKE 'identifier:%'
  AND `player_identifier` IS NULL;
