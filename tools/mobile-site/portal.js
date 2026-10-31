'use strict';
const screen = document.getElementById('screen');
const status = document.getElementById('status');
const notice = document.getElementById('notice');
const direct = document.getElementById('direct');
let currentUrl = null;
let busy = false;
function validOrigin(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || !/^[a-z0-9-]+\.trycloudflare\.com$/.test(url.hostname) || url.port || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw Error('올바르지 않은 지도 주소');
  return url.href;
}
async function refresh(force = false) {
  if (busy) return;
  busy = true;
  try {
    const response = await fetch(`connection.json?t=${Date.now()}`, {cache:'no-store',signal:AbortSignal.timeout(8000)});
    if (!response.ok) throw Error('지도 접속 정보를 가져오지 못했습니다');
    const connection = await response.json();
    const url = validOrigin(connection.url);
    if (force || url !== currentUrl) {
      screen.src = url;
      screen.hidden = false;
      direct.href = url;
      direct.hidden = false;
      currentUrl = url;
    }
    notice.hidden = true;
    status.textContent = '고정 주소 · 연결 정보 자동 확인';
    status.title = '이 문구는 PC의 온라인 상태를 의미하지 않습니다. 현재 연결 상태는 지도에 표시됩니다.';
  } catch (error) {
    status.textContent = '주소 확인 실패 · 새로고침으로 다시 연결';
    if (!currentUrl) {
      notice.hidden = false;
      notice.textContent = '지도를 불러오지 못했습니다. PC와 인터넷 연결을 확인한 뒤 새로고침해 주세요.';
    }
  } finally { busy = false; }
}
document.getElementById('refresh').addEventListener('click',()=>refresh(true));
document.addEventListener('visibilitychange',()=>{if(!document.hidden)void refresh();});
void refresh();
setInterval(()=>{if(!document.hidden)void refresh();},60000);
