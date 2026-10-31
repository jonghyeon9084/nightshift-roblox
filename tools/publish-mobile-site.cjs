'use strict';
// A separate generated-only checkout keeps live development files out of site publication.
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const branch = 'codex/mobile-monitor';
const repository = 'https://github.com/jonghyeon9084/nightshift-roblox.git';
const stableUrl = 'https://jonghyeon9084.github.io/nightshift-roblox/';
function validateUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || !/^[a-z0-9-]+\.trycloudflare\.com$/.test(url.hostname) || url.username || url.password || url.port || url.pathname !== '/' || url.search || url.hash) throw Error('Only a public root HTTPS Quick Tunnel address can be published');
  return url.href;
}
function publish() {
  const access = JSON.parse(fs.readFileSync(path.join(root,'.setup/mobile-access.json'),'utf8').replace(/^\uFEFF/,''));
  if (access.publicAccess !== true) throw Error('Only the already-public read-only map may be published');
  const url = validateUrl(fs.readFileSync(path.join(root,'.setup/mobile-link.txt'),'utf8').trim());
  const checkout = path.join(root,'.setup/mobile-site-publisher');
  fs.mkdirSync(checkout,{recursive:true});
  const git = args => execFileSync('git',['-c','credential.interactive=never',...args],{cwd:checkout,windowsHide:true,encoding:'utf8',timeout:45000,stdio:['ignore','pipe','pipe']}).trim();
  const files = ['index.html','portal.js','connection.json','.nojekyll'];
  const initialized = fs.existsSync(path.join(checkout,'.git'));
  if (!initialized) {
    if (fs.readdirSync(checkout).length) throw Error('Publisher directory is not empty; refusing to adopt it');
    git(['init','-b',branch]);
    git(['remote','add','origin',repository]);
  }
  if (git(['remote','get-url','origin']) !== repository || git(['symbolic-ref','--short','HEAD']) !== branch) throw Error('Unexpected publisher checkout or branch');
  git(['config','user.name','jonghyeon9084']);
  git(['config','user.email','183079622+jonghyeon9084@users.noreply.github.com']);
  const remoteExists = git(['ls-remote','--heads','origin',`refs/heads/${branch}`]);
  if (remoteExists) {
    git(['fetch','origin',branch]);
    let hasHead = false;
    try { git(['rev-parse','--verify','HEAD']); hasHead = true; } catch {}
    if (hasHead) git(['merge','--ff-only',`origin/${branch}`]);
    else git(['checkout','-B',branch,`origin/${branch}`]);
  }
  for (const file of ['index.html','portal.js']) fs.copyFileSync(path.join(root,'tools/mobile-site',file),path.join(checkout,file));
  fs.writeFileSync(path.join(checkout,'.nojekyll'),'');
  let previous;
  try { previous = JSON.parse(fs.readFileSync(path.join(checkout,'connection.json'),'utf8')); } catch {}
  if (previous?.url !== url) fs.writeFileSync(path.join(checkout,'connection.json'),JSON.stringify({version:1,url,updatedAt:new Date().toISOString()},null,2)+'\n');
  git(['add','--',...files]);
  const changed = git(['diff','--cached','--name-only']);
  if (changed) git(['commit','-m','Update public NightShift mobile monitor']);
  git(['push','origin',`HEAD:refs/heads/${branch}`]);
  fs.writeFileSync(path.join(root,'.setup/mobile-stable-link.txt'),stableUrl+'\n');
  const result = {kind:'PAGES_SOURCE_PUBLISHED',stableUrl,branch,tunnelUrl:url,commit:git(['rev-parse','HEAD']),changed:!!changed};
  fs.writeFileSync(path.join(root,'.setup/mobile-site-publication.json'),JSON.stringify(result,null,2)+'\n');
  return result;
}
if(require.main===module){try{console.log(JSON.stringify(publish()));}catch(error){console.error(error.message);process.exitCode=1;}}
module.exports={validateUrl};
