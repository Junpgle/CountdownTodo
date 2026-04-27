const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('D:/Codes/Android/math_quiz_app/aliyun_debug/database_debug.db');

db.serialize(() => {
    db.all("SELECT name, sql FROM sqlite_master WHERE type='trigger'", (err, rows) => {
        if (err) {
            console.error(err);
            process.exit(1);
        }
        console.log(JSON.stringify(rows));
        db.close();
        process.exit(0);
    });
});
