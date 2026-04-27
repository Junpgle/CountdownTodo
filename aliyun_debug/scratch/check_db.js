const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('./database_debug.db');
db.all("SELECT name FROM sqlite_master WHERE type='table'", (err, rows) => {
    if (err) {
        console.error(err);
        process.exit(1);
    }
    console.log(JSON.stringify(rows));
    process.exit(0);
});
