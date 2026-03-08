const https = require('https');
const token = '1.e80109e10db5222a85c6c3cbec388a68cd5eef3035dc379a563dbc8f774b5045';
const from = Date.now() - 30 * 24 * 60 * 60 * 1000;

const req = https.request({
  hostname: 'mathquiz.junpgle.me',
  path: '/api/pomodoro/records?from=' + from,
  method: 'GET',
  headers: { 'Authorization': 'Bearer ' + token }
}, res => {
  let body = '';
  res.on('data', c => body += c);
  res.on('end', () => {
    console.log('HTTP Status:', res.statusCode);
    try {
      const arr = JSON.parse(body);
      console.log('Total records:', arr.length);
      arr.slice(0, 5).forEach(r => {
        console.log(JSON.stringify({
          uuid: r.uuid ? r.uuid.slice(0, 8) : null,
          title: r.todo_title,
          tags: r.tag_uuids,
          start_time: r.start_time,
          updated_at: r.updated_at,
        }));
      });
    } catch (e) {
      console.log('Parse error:', e.message);
      console.log('Raw:', body.slice(0, 500));
    }
    process.exit(0);
  });
});
req.setTimeout(15000, () => { console.error('Timeout'); process.exit(1); });
req.on('error', e => { console.error('Error:', e.message); process.exit(1); });
req.end();

