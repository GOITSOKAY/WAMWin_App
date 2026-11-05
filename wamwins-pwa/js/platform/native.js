/** Capacitor integration. Everything is optional: on the web these calls do nothing. */
export const isNative = () => !!window.Capacitor?.isNativePlatform?.();
export function initNative(router) {
  if (!isNative()) return;
  document.documentElement.classList.add('native');
  const P = window.Capacitor.Plugins || {};
  P.App?.addListener?.('backButton', () => { if (router.canGoBack()) history.back(); else P.App.exitApp?.(); });
  P.StatusBar?.setOverlaysWebView?.({ overlay: true });
  P.StatusBar?.setStyle?.({ style: 'DARK' });
  P.SplashScreen?.hide?.();
}
