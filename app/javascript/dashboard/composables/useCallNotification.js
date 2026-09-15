// Desktop notification + blinking tab title for an incoming SIP call, so a ringing
// call is noticed while the agent is in another tab or window. Permission is asked
// the first time the agent registers the softphone (a user gesture already happened).
const BLINK_MS = 1000;

let notification = null;
let blinkTimer = null;
let originalTitle = null;

export const requestCallNotificationPermission = () => {
  if (!('Notification' in window)) return;
  if (Notification.permission === 'default') {
    Notification.requestPermission().catch(() => {});
  }
};

const stopBlink = () => {
  if (blinkTimer) clearInterval(blinkTimer);
  blinkTimer = null;
  if (originalTitle !== null) document.title = originalTitle;
  originalTitle = null;
};

export const useCallNotification = () => {
  const notify = ({ title, body, onClick }) => {
    if (originalTitle === null) {
      originalTitle = document.title;
      let flip = false;
      blinkTimer = setInterval(() => {
        flip = !flip;
        document.title = flip ? `☎ ${title}` : originalTitle;
      }, BLINK_MS);
    }
    if (
      'Notification' in window &&
      Notification.permission === 'granted' &&
      (document.hidden || !document.hasFocus())
    ) {
      try {
        notification = new Notification(title, {
          body,
          tag: 'chatwoot-telephony',
          requireInteraction: true,
        });
        notification.onclick = () => {
          window.focus();
          onClick?.();
          notification?.close();
        };
      } catch (e) {
        notification = null;
      }
    }
  };

  const clear = () => {
    stopBlink();
    notification?.close();
    notification = null;
  };

  return { notify, clear };
};
