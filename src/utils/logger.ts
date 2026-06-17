import winston from "winston";
import path from "path";

const logDir = path.join(process.cwd(), "logs");

const customFormat = winston.format.combine(
  winston.format.timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
  winston.format.errors({ stack: true }),
  winston.format.printf(({ timestamp, level, message, stack }) => {
    return `${timestamp} [${level.toUpperCase()}]: ${stack || message}`;
  })
);

export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: customFormat,
  transports: [
    // Console output
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        customFormat
      ),
    }),
    // Error log file
    new winston.transports.File({
      filename: path.join(logDir, "errors.log"),
      level: "error",
      maxsize: 5242880, // 5MB
      maxFiles: 5,
    }),
    // Activity log file
    new winston.transports.File({
      filename: path.join(logDir, "activity.log"),
      maxsize: 5242880,
      maxFiles: 5,
    }),
  ],
});

// Security-specific logger
export const securityLogger = winston.createLogger({
  level: "info",
  format: customFormat,
  transports: [
    new winston.transports.File({
      filename: path.join(logDir, "security.log"),
      maxsize: 5242880,
      maxFiles: 10,
    }),
  ],
});
