import app from './app.js';
import { prisma } from './db.js';
import { startPushWorker } from './push.js';
import { startConnectReminders } from './connect_reminders.js';
const stopPush = startPushWorker();
const stopReminders = startConnectReminders();

const PORT = process.env.PORT || 4000;
const server = app.listen(PORT, '0.0.0.0', () => console.log(`D2F backend listening on port ${PORT}`));

async function stop() {
  stopReminders();
  stopPush();
  server.close(async () => { await prisma.$disconnect(); process.exit(0); });
}
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
