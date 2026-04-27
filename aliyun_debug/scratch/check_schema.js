const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('D:/Codes/Android/math_quiz_app/aliyun_debug/database_debug.db');

db.serialize(() => {
    db.all("SELECT name FROM sqlite_master WHERE type='table'", (err, tables) => {
        if (err) {
            console.error(err);
            process.exit(1);
        }
        
        const checkNextTable = (index) => {
            if (index >= tables.length) {
                db.close();
                return;
            }
            
            const tableName = tables[index].name;
            db.all(`PRAGMA table_info(${tableName})`, (err, columns) => {
                if (err) {
                    console.error(`Error checking ${tableName}:`, err);
                } else {
                    console.log(`Table: ${tableName}`);
                    console.log(columns.map(c => c.name).join(', '));
                    console.log('---');
                }
                checkNextTable(index + 1);
            });
        };
        
        checkNextTable(0);
    });
});
