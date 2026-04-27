const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('./database.db');

const userId = 23;

db.serialize(() => {
  db.run('BEGIN TRANSACTION');

  console.log(`Starting deletion for User ID: ${userId}...`);

  // 1. Delete user from users table
  db.run('DELETE FROM users WHERE id = ?', [userId], function(err) {
    if (err) console.error('Error deleting user:', err.message);
    else console.log(`Deleted user ${userId}: ${this.changes} rows affected.`);
  });

  // 2. Delete todos
  db.run('DELETE FROM todos WHERE user_id = ?', [userId], function(err) {
    if (err) console.error('Error deleting todos:', err.message);
    else console.log(`Deleted todos for user ${userId}: ${this.changes} rows affected.`);
  });

  // 3. Delete courses
  db.run('DELETE FROM courses WHERE user_id = ?', [userId], function(err) {
    if (err) console.error('Error deleting courses:', err.message);
    else console.log(`Deleted courses for user ${userId}: ${this.changes} rows affected.`);
  });

  // 4. Delete pomodoro records
  db.run('DELETE FROM pomodoro_records WHERE user_id = ?', [userId], function(err) {
    if (err) console.error('Error deleting pomodoro_records:', err.message);
    else console.log(`Deleted pomodoro records for user ${userId}: ${this.changes} rows affected.`);
  });

  // 5. Delete time logs
  db.run('DELETE FROM time_logs WHERE user_id = ?', [userId], function(err) {
    if (err) console.error('Error deleting time_logs:', err.message);
    else console.log(`Deleted time logs for user ${userId}: ${this.changes} rows affected.`);
  });

  // 6. Delete team membership
  db.run('DELETE FROM team_members WHERE user_id = ?', [userId], function(err) {
    if (err) console.error('Error deleting team_members:', err.message);
    else console.log(`Deleted team membership for user ${userId}: ${this.changes} rows affected.`);
  });

  // 7. Delete todo groups
  db.run('DELETE FROM todo_groups WHERE user_id = ?', [userId], function(err) {
    if (err) console.error('Error deleting todo_groups:', err.message);
    else console.log(`Deleted todo groups for user ${userId}: ${this.changes} rows affected.`);
  });

  db.run('COMMIT', (err) => {
    if (err) {
      console.error('Transaction failed:', err.message);
      db.run('ROLLBACK');
    } else {
      console.log('Successfully deleted user 23 and all related data.');
    }
    db.close();
  });
});
