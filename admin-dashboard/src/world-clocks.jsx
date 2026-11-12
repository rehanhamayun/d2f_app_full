import { useEffect, useState } from 'react';
import { Clock3, Globe2 } from 'lucide-react';
import { COUNTRY_ZONES, dashboardTimezone } from './timezones.js';

export function DashboardTimezone() {
  const [zone, setZone] = useState(dashboardTimezone);
  return <label className="dashboard-timezone"><Globe2 size={16} /><select aria-label="Dashboard time zone" value={zone} onChange={e => {
    setZone(e.target.value); localStorage.setItem('d2f-timezone', e.target.value); window.dispatchEvent(new Event('d2f-timezone'));
  }}>{Object.entries(COUNTRY_ZONES).map(([country, zones]) => <optgroup key={country} label={country}>{zones.map(z => <option value={z} key={z}>{country === 'United States' ? 'USA' : country} · {z.split('/').at(-1).replaceAll('_', ' ')}</option>)}</optgroup>)}<option value="UTC">UTC</option></select></label>;
}
export function WorldClocks() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => { const t = setInterval(() => setNow(new Date()), 30000); return () => clearInterval(t); }, []);
  return <section className="world-clock-strip" aria-label="Network local times"><div className="world-clock-intro"><Clock3 size={20} /><span>One network.<b>Every local time.</b></span></div>{[
    ['US', 'USA · New York', 'America/New_York'], ['US', 'USA · Omaha', 'America/Chicago'], ['EU', 'Belgium · Brussels', 'Europe/Brussels'], ['TG', 'Togo · Lomé', 'Africa/Lome'],
  ].map(([code, city, zone]) => <div className="world-clock" key={zone}><span className="clock-country">{code}</span><div><small>{city}</small><b>{now.toLocaleTimeString('en-US', { timeZone: zone, hour: 'numeric', minute: '2-digit' })}</b><span>{now.toLocaleDateString('en-US', { timeZone: zone, month: 'short', day: 'numeric', timeZoneName: 'short' })}</span></div></div>)}</section>;
}
