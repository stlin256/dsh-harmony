import { openStore } from './store.mjs';
if (process.argv[2] !== '--revoke-owner-and-all-devices') {
  console.error('Stop gateway, back up database, then pass --revoke-owner-and-all-devices to reset Passkeys and revoke all devices.');
  process.exit(1);
}
const db = openStore(process.env.DATA_FILE || './data/pocket.sqlite');
db.exec('BEGIN IMMEDIATE; DELETE FROM credentials; DELETE FROM sessions; DELETE FROM devices; DELETE FROM jobs; DELETE FROM pending_actions; DELETE FROM task_states; COMMIT;');
db.close();
console.log('Owner credentials and notification registrations revoked');
