#!/usr/bin/env node
/**
 * scripts/auth-bcrypt.js
 *
 * Generate a bcrypt cost-12 hash for the Crystallux admin/client user
 * seed. Run locally; the hash never travels through the repo unless
 * you choose to copy it into a migration.
 *
 * Usage:
 *   1) Install bcryptjs once (no native deps):
 *        npm i -g bcryptjs        # or
 *        npx bcryptjs --version   # to confirm available
 *      Or, in this repo:
 *        npm i bcryptjs --no-save
 *
 *   2) Run with the password as the first argument (avoid quotes the
 *      shell will swallow; on Windows PowerShell use single quotes):
 *        node scripts/auth-bcrypt.js 'YourTempPassw0rd!'
 *
 *   3) Take the printed hash and run, against your Supabase project,
 *      ONE of these (whichever matches your need):
 *
 *      -- Update Mary's seed row (created by the migration):
 *      UPDATE auth_users
 *         SET password_hash = '<paste-hash-here>',
 *             failed_login_attempts = 0,
 *             locked_until = NULL
 *       WHERE email = 'info@crystallux.org';
 *
 *      -- Create a fresh admin (e.g. a backup admin):
 *      INSERT INTO auth_users (email, password_hash, user_role, email_verified, email_verified_at)
 *      VALUES ('backup-admin@crystallux.org', '<paste-hash-here>', 'admin', true, now());
 *
 *      -- Create a client login bound to a clients.id:
 *      INSERT INTO auth_users (email, password_hash, user_role, client_id, email_verified, email_verified_at)
 *      VALUES ('founder@blonai.example', '<paste-hash-here>', 'client',
 *              '<clients-uuid>', true, now());
 *
 *   4) On Mary's first real login, immediately use the password-reset
 *      flow to issue a fresh hash; the migration's placeholder is then
 *      irrelevant.
 *
 * Notes:
 *   - Cost factor 12 matches the verifier in workflows/api/auth/.
 *   - bcrypt outputs $2b$ prefix; n8n's bcryptjs accepts this.
 *   - Do not commit a real production password hash via this repo.
 *     Run the SQL UPDATE directly against the database from your
 *     local terminal.
 */

const COST = 12;

async function main() {
  const password = process.argv[2];
  if (!password || password.length < 12) {
    console.error('ERROR: pass a password of at least 12 characters as the first argument.');
    console.error('Example: node scripts/auth-bcrypt.js \'Crystallux-Init-2026!\'');
    process.exit(2);
  }

  let bcrypt;
  try {
    bcrypt = require('bcryptjs');
  } catch (e) {
    console.error('ERROR: bcryptjs not found. Install it first:');
    console.error('  npm i bcryptjs --no-save');
    console.error('  (or globally:  npm i -g bcryptjs)');
    process.exit(3);
  }

  const hash = await bcrypt.hash(password, COST);
  console.log('---');
  console.log('Bcrypt cost-12 hash (paste into UPDATE auth_users SET password_hash = ...):');
  console.log(hash);
  console.log('---');
  console.log('Verification round-trip:', await bcrypt.compare(password, hash) ? 'OK' : 'FAIL');
}

main().catch(e => { console.error(e); process.exit(1); });
