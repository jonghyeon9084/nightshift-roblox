// Separate read-only gateway: never exposes Maestro's command endpoint or workspace files.
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const configPath=path.join(root,'.setup/mobile-access.json');
function equal(a,b) { const x=Buffer.from(a||''),y=Buffer.from(b||'');return x.length===y.length&&crypto.timingSafeEqual(x,y); }
function publicFrameHeaders(headers, publicAccess) {
  const result={...headers};
  if(publicAccess && typeof result['content-security-policy']==='string') {
    result['content-security-policy']=result['content-security-policy'].replace(/frame-ancestors\s+'none'/, 'frame-ancestors https://jonghyeon9084.github.io');
  }
  return result;
}
function createGateway(token,{publicAccess=false}={}) {
  if(!/^[a-f0-9]{64}$/.test(token))throw new Error('A random 256-bit access key is required');
  return http.createServer((req,res)=>{
    res.setHeader('Cache-Control','no-store');
    res.setHeader('Referrer-Policy','no-referrer');
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('X-Robots-Tag','noindex, nofollow');
    if(req.method!=='GET'){res.writeHead(405);return res.end();}
    const url=new URL(req.url,'http://localhost');
    if(url.pathname.startsWith('/access/')&&equal(url.pathname.slice(8),token)) {
      res.setHeader('Set-Cookie',publicAccess?'nightshift_access=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0':`nightshift_access=${token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=2592000`);
      res.writeHead(303,{Location:'/'});return res.end();
    }
    const cookie=(req.headers.cookie||'').split(';').map(s=>s.trim()).find(s=>s.startsWith('nightshift_access='))?.slice(18);
    if(!publicAccess&&!equal(cookie,token)) {res.writeHead(401,{'Content-Type':'text/plain; charset=utf-8'});return res.end('전용 접속 링크로 열어 주세요. NightShift 모바일 지도');}
    if(!['/','/app.js','/model.js','/fleet.js','/style.css','/api/state','/api/history','/api/history/export'].includes(url.pathname)){res.writeHead(404);return res.end();}
    const upstream=http.get({host:'127.0.0.1',port:43821,path:url.pathname+url.search,headers:{Host:'127.0.0.1:43821'},timeout:15000},response=>{
      res.writeHead(response.statusCode,publicFrameHeaders(response.headers,publicAccess));response.pipe(res);
    });
    upstream.on('timeout',()=>upstream.destroy());
    upstream.on('error',()=>{if(!res.headersSent)res.writeHead(503,{'Content-Type':'text/plain; charset=utf-8'});res.end('PC 지도 서버에 연결할 수 없습니다.');});
  });
}
if(require.main===module) {
  fs.mkdirSync(path.dirname(configPath),{recursive:true});
  if(!fs.existsSync(configPath))fs.writeFileSync(configPath,JSON.stringify({token:crypto.randomBytes(32).toString('hex')}),{mode:0o600});
  const config=JSON.parse(fs.readFileSync(configPath,'utf8'));
  const server=createGateway(config.token,{publicAccess:config.publicAccess===true});
  server.listen(43822,'127.0.0.1',()=>{fs.writeFileSync(path.join(root,'.setup/mobile-gateway.pid'),String(process.pid));console.log('NightShift read-only mobile gateway ready');});
  server.on('error',error=>{console.error(error.message);process.exit(1);});
}
module.exports={createGateway,publicFrameHeaders};
