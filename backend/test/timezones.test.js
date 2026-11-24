import test from 'node:test';
import assert from 'node:assert/strict';
import { routeZone, localToInstant, tripTiming } from '../src/timezones.js';

test('Connect interprets departure-city local times, independent of server or viewer country', () => {
  assert.equal(routeZone('New York, USA'), 'America/New_York');
  assert.equal(routeZone('Omaha, NE, USA'), 'America/Chicago');
  assert.equal(routeZone('Lomé, Togo'), 'Africa/Lome');
  assert.equal(routeZone('Paris, France'), 'Europe/Paris');
  assert.equal(localToInstant('2026-12-15T12:00', 'America/New_York').toISOString(), '2026-12-15T17:00:00.000Z');
  assert.equal(localToInstant('2026-07-15T12:00', 'America/New_York').toISOString(), '2026-07-15T16:00:00.000Z');
  assert.equal(localToInstant('2026-12-15T12:00', 'Africa/Lome').toISOString(), '2026-12-15T12:00:00.000Z');
  assert.throws(() => routeZone('Unknown city, USA'), /Choose a time zone/);
  assert.throws(() => routeZone('Paris, France', 'America/Chicago'), /Choose a time zone/);
  assert.throws(() => localToInstant('2026-02-30T12:00', 'Africa/Lome'), /valid local date/);
  assert.throws(() => localToInstant('2026-03-08T02:30', 'America/New_York'), /does not exist/);
  assert.throws(() => localToInstant('2026-11-01T01:30', 'America/New_York'), /occurs twice/);
  assert.equal(localToInstant('2026-11-01T01:30', 'America/New_York', 'EARLIER').toISOString(), '2026-11-01T05:30:00.000Z');
  assert.equal(localToInstant('2026-11-01T01:30', 'America/New_York', 'LATER').toISOString(), '2026-11-01T06:30:00.000Z');
  const t = tripTiming({ origin: 'New York, USA', destination: 'Lomé, Togo', departureAt: '2026-12-15T17:00:00Z' });
  assert.match(t.departureLocal, /12:00 PM/);
  assert.match(t.departureAtDestination, /5:00 PM/);
});
