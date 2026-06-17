-- ============================================================
-- CAD-MDT Standalone Database Schema
-- For ESX Legacy + oxmysql
-- ============================================================

-- Officers (linked to ESX users table)
CREATE TABLE IF NOT EXISTS `mdtx_officers` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `identifier` VARCHAR(60) NOT NULL,
  `firstname` VARCHAR(50) NOT NULL,
  `lastname` VARCHAR(50) NOT NULL,
  `badge_number` VARCHAR(20) NOT NULL,
  `department` VARCHAR(50) NOT NULL DEFAULT 'LSPD',
  `rank` VARCHAR(50) NOT NULL DEFAULT 'Officer',
  `callsign` VARCHAR(20) DEFAULT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `status` VARCHAR(30) NOT NULL DEFAULT 'OFF_DUTY',
  `status_detail` VARCHAR(100) DEFAULT NULL,
  `on_duty` TINYINT(1) NOT NULL DEFAULT 0,
  `last_lat` DOUBLE DEFAULT NULL,
  `last_lng` DOUBLE DEFAULT NULL,
  `last_update` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Civilian profiles (multi-character support)
CREATE TABLE IF NOT EXISTS `mdtx_civilians` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `identifier` VARCHAR(60) NOT NULL,
  `firstname` VARCHAR(50) NOT NULL,
  `lastname` VARCHAR(50) NOT NULL,
  `date_of_birth` DATE DEFAULT NULL,
  `gender` VARCHAR(20) DEFAULT NULL,
  `address` VARCHAR(255) DEFAULT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `is_active` TINYINT(1) NOT NULL DEFAULT 0,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_identifier` (`identifier`),
  INDEX `idx_active` (`identifier`, `is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Licenses
CREATE TABLE IF NOT EXISTS `mdtx_licenses` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `civilian_id` INT NOT NULL,
  `type` VARCHAR(32) NOT NULL,
  `number` VARCHAR(32) NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'VALID',
  `issued_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  `expires_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_civilian` (`civilian_id`),
  UNIQUE KEY `uk_number` (`number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Vehicles
CREATE TABLE IF NOT EXISTS `mdtx_vehicles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `plate` VARCHAR(10) NOT NULL,
  `model` VARCHAR(64) NOT NULL,
  `color` VARCHAR(32) NOT NULL,
  `year` INT DEFAULT NULL,
  `vin` VARCHAR(32) DEFAULT NULL,
  `owner_id` INT NOT NULL,
  `registration_status` VARCHAR(20) NOT NULL DEFAULT 'VALID',
  `insurance_status` VARCHAR(20) NOT NULL DEFAULT 'NONE',
  `stolen` TINYINT(1) NOT NULL DEFAULT 0,
  `flags` TEXT DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_plate` (`plate`),
  INDEX `idx_owner` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Warrants
CREATE TABLE IF NOT EXISTS `mdtx_warrants` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `warrant_number` VARCHAR(32) NOT NULL,
  `civilian_id` INT NOT NULL,
  `type` VARCHAR(32) NOT NULL DEFAULT 'ARREST',
  `charges` TEXT NOT NULL,
  `issued_by` VARCHAR(128) NOT NULL,
  `issued_at` DATETIME DEFAULT CURRENT_TIMESTAMP,
  `expires_at` DATETIME DEFAULT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_warrant_number` (`warrant_number`),
  INDEX `idx_civilian` (`civilian_id`),
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Incident Reports
CREATE TABLE IF NOT EXISTS `mdtx_incident_reports` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `report_number` VARCHAR(32) NOT NULL,
  `officer_identifier` VARCHAR(60) NOT NULL,
  `location` VARCHAR(255) NOT NULL,
  `date_time` DATETIME NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `narrative` TEXT NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
  `approved_by` VARCHAR(128) DEFAULT NULL,
  `approved_at` DATETIME DEFAULT NULL,
  `signature_data` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_report_number` (`report_number`),
  INDEX `idx_officer` (`officer_identifier`),
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Arrest Reports
CREATE TABLE IF NOT EXISTS `mdtx_arrest_reports` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `report_number` VARCHAR(32) NOT NULL,
  `officer_identifier` VARCHAR(60) NOT NULL,
  `civilian_id` INT NOT NULL,
  `location` VARCHAR(255) NOT NULL,
  `date_time` DATETIME NOT NULL,
  `narrative` TEXT NOT NULL,
  `charges` TEXT NOT NULL,
  `jail_time_days` INT DEFAULT NULL,
  `miranda_read` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_report_number` (`report_number`),
  INDEX `idx_civilian` (`civilian_id`),
  INDEX `idx_officer` (`officer_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Citations
CREATE TABLE IF NOT EXISTS `mdtx_citations` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citation_number` VARCHAR(32) NOT NULL,
  `officer_identifier` VARCHAR(60) NOT NULL,
  `civilian_id` INT NOT NULL,
  `location` VARCHAR(255) NOT NULL,
  `date_time` DATETIME NOT NULL,
  `violation` VARCHAR(255) NOT NULL,
  `amount` DECIMAL(10,2) DEFAULT NULL,
  `description` TEXT DEFAULT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'UNPAID',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_citation_number` (`citation_number`),
  INDEX `idx_civilian` (`civilian_id`),
  INDEX `idx_officer` (`officer_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Warnings
CREATE TABLE IF NOT EXISTS `mdtx_warnings` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `officer_identifier` VARCHAR(60) NOT NULL,
  `civilian_id` INT NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `description` TEXT NOT NULL,
  `location` VARCHAR(255) DEFAULT NULL,
  `date_time` DATETIME NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_civilian` (`civilian_id`),
  INDEX `idx_officer` (`officer_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Use of Force Reports
CREATE TABLE IF NOT EXISTS `mdtx_uof_reports` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `report_number` VARCHAR(32) NOT NULL,
  `officer_identifier` VARCHAR(60) NOT NULL,
  `location` VARCHAR(255) NOT NULL,
  `date_time` DATETIME NOT NULL,
  `force_type` VARCHAR(64) NOT NULL,
  `subject_name` VARCHAR(128) NOT NULL,
  `narrative` TEXT NOT NULL,
  `witness_info` TEXT DEFAULT NULL,
  `injuries` TEXT DEFAULT NULL,
  `medical_attention` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
  `approved_by` VARCHAR(128) DEFAULT NULL,
  `approved_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_report_number` (`report_number`),
  INDEX `idx_officer` (`officer_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- BOLOs (Be On the Lookout)
CREATE TABLE IF NOT EXISTS `mdtx_bolos` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `type` VARCHAR(32) NOT NULL DEFAULT 'PERSON',
  `priority` VARCHAR(20) NOT NULL DEFAULT 'MEDIUM',
  `description` TEXT NOT NULL,
  `last_known_location` VARCHAR(255) DEFAULT NULL,
  `creator_identifier` VARCHAR(60) NOT NULL,
  `target_civilian_id` INT DEFAULT NULL,
  `target_vehicle_id` INT DEFAULT NULL,
  `expires_at` DATETIME DEFAULT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_active` (`active`),
  INDEX `idx_creator` (`creator_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dispatch Calls
CREATE TABLE IF NOT EXISTS `mdtx_dispatch_calls` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `call_number` VARCHAR(32) NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `description` TEXT NOT NULL,
  `location` VARCHAR(255) NOT NULL,
  `lat` DOUBLE DEFAULT NULL,
  `lng` DOUBLE DEFAULT NULL,
  `priority` VARCHAR(20) NOT NULL DEFAULT 'PRIORITY_3',
  `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `creator_identifier` VARCHAR(60) NOT NULL,
  `handler_identifier` VARCHAR(60) DEFAULT NULL,
  `completed_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_call_number` (`call_number`),
  INDEX `idx_status` (`status`),
  INDEX `idx_priority` (`priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Emergency (911) Calls
CREATE TABLE IF NOT EXISTS `mdtx_emergency_calls` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `caller_name` VARCHAR(128) NOT NULL DEFAULT 'Unknown',
  `caller_phone` VARCHAR(20) DEFAULT NULL,
  `description` TEXT NOT NULL,
  `location` VARCHAR(255) NOT NULL,
  `lat` DOUBLE DEFAULT NULL,
  `lng` DOUBLE DEFAULT NULL,
  `type` VARCHAR(64) NOT NULL DEFAULT 'Emergency',
  `status` VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Evidence
CREATE TABLE IF NOT EXISTS `mdtx_evidence` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `evidence_number` VARCHAR(32) NOT NULL,
  `type` VARCHAR(32) NOT NULL DEFAULT 'NOTE',
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `officer_identifier` VARCHAR(60) NOT NULL,
  `report_type` VARCHAR(32) DEFAULT NULL,
  `report_id` INT DEFAULT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_evidence_number` (`evidence_number`),
  INDEX `idx_report` (`report_type`, `report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Notifications
CREATE TABLE IF NOT EXISTS `mdtx_notifications` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `type` VARCHAR(64) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `priority` VARCHAR(20) NOT NULL DEFAULT 'NORMAL',
  `target_identifier` VARCHAR(60) DEFAULT NULL,
  `read` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_target` (`target_identifier`),
  INDEX `idx_read` (`read`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
