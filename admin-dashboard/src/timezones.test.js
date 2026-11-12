import { beforeEach, expect, it } from 'vitest';
import { dateTime, dateTimeFromLocalInput, dateTimeLocalInput } from './operations-ui.jsx';
import { inferredZone } from './timezones.js';
beforeEach(() => localStorage.clear());
it('dashboard timezone changes update display and appointment input conversion', () => {
  localStorage.setItem('d2f-timezone', 'Africa/Lome');
  expect(dateTime('2026-12-15T17:00:00Z')).toContain('5:00 PM');
  expect(dateTimeLocalInput('2026-12-15T17:00:00Z')).toBe('2026-12-15T17:00');
  expect(dateTimeFromLocalInput('2026-12-15T17:00')).toBe('2026-12-15T17:00:00.000Z');
  localStorage.setItem('d2f-timezone', 'America/New_York');
  expect(dateTime('2026-12-15T17:00:00Z')).toContain('12:00 PM');
  expect(() => dateTimeFromLocalInput('2026-03-08T02:30')).toThrow(/does not exist/);
  expect(() => dateTimeFromLocalInput('2026-11-01T01:30')).toThrow(/occurs twice/);
  expect(inferredZone('Unknown town, USA')).toBeNull();
});
