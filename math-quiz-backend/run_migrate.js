const https = require('https');
const token = '1.e80109e10db5222a85c6c3cbec388a68cd5eef3035dc379a563dbc8f774b5045';
const data = '{}';

const req = https.request({
  hostname: 'mathquiz.junpgle.me',
  path: '/api/admin/migrate',
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ' + token,
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(data)
  }
}, res => {
  let body = '';
  res.on('data', c => body += c);
  res.on('end', () => {
    console.log('Status:', res.statusCode);
    console.log('Body:', body);
  });
});

req.on('error', e => console.error('Error:', e.message));
req.write(data);
req.end();

