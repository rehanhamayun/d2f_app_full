import { useEffect, useRef, useState } from 'react';
import { Bell, CheckCheck, X } from 'lucide-react';
import { request } from './api.js';
import { zonedDate } from './timezones.js';

export function NotificationBell({ token }) {
  const [open, setOpen] = useState(false), [data, setData] = useState({ items: [], unread: 0 }), [error, setError] = useState('');
  const container = useRef(null);
  useEffect(() => {
    let active = true;
    const load = async () => {
      if (!token) return;
      try { const d = await request('/notifications?limit=30', { token }); if (active) { setData({ items: d.items || [], unread: d.unread || 0 }); setError(''); } } catch { if (active) setError('Updates could not be loaded. Try again shortly.'); }
    };
    load(); const timer = setInterval(load, 20000);
    return () => { active = false; clearInterval(timer); };
  }, [token]);
  useEffect(() => {
    if (!open) return;
    const dismiss = e => { if (e.key === 'Escape' || (e.type === 'pointerdown' && !container.current?.contains(e.target))) setOpen(false); };
    document.addEventListener('pointerdown', dismiss); document.addEventListener('keydown', dismiss);
    return () => { document.removeEventListener('pointerdown', dismiss); document.removeEventListener('keydown', dismiss); };
  }, [open]);
  async function read(id) {
    try {
      await request(id ? `/notifications/${id}/read` : '/notifications/read-all', { token, method: 'POST' });
      setData(d => ({ unread: id ? Math.max(0, d.unread - (d.items.find(i => i.id === id)?.read ? 0 : 1)) : 0, items: d.items.map(n => !id || n.id === id ? { ...n, read: true } : n) }));
    } catch { setError('Could not mark updates as read. Please try again.'); }
  }
  return <div className="notification-center" ref={container}><button className="icon-button notification-trigger" aria-label={`Notifications${data.unread ? `, ${data.unread} unread` : ''}`} aria-expanded={open} onClick={() => setOpen(!open)}><Bell size={20} />{data.unread > 0 && <span>{data.unread > 99 ? '99+' : data.unread}</span>}</button>{open && <section className="notification-popover" aria-label="Notification inbox"><header><div><small>YOUR OPERATION</small><h2>Latest updates <span>{data.unread}</span></h2></div><button className="icon-button" aria-label="Close notifications" onClick={() => setOpen(false)}><X size={18} /></button></header><button className="text-button" disabled={!data.unread} onClick={() => read()}><CheckCheck size={16} /> Mark all as read</button>{error && <p role="alert">{error}</p>}<div className="notification-list">{data.items.length ? data.items.map(n => <button key={n.id} className={`notification-item ${n.read ? '' : 'unread'}`} onClick={() => read(n.id)}><span className="notification-dot" /><span><b>{n.title}</b><span>{n.body}</span><time>{zonedDate(n.createdAt)}</time></span></button>) : <p className="notification-empty">You're all caught up. New operational updates will appear here.</p>}</div></section>}</div>;
}
