/**
 * Convert a datetime-local input value (e.g. "2024-06-16T14:30") or any date string
 * to a full ISO 8601 string (e.g. "2024-06-16T14:30:00.000Z") that passes
 * Zod's z.string().datetime() validation.
 */
export function toISODateTime(value: string | undefined | null): string {
  if (!value) return new Date().toISOString();
  const d = new Date(value);
  if (!isNaN(d.getTime())) return d.toISOString();
  return new Date().toISOString();
}
