// Next's internal request URL may normalize loopback to localhost.
// Compare the browser's Origin to Host, and accept only this local app.
export function isLocalWriteRequest(request: Request) {
  const origin = request.headers.get('origin');
  const host = request.headers.get('host');
  if (!origin || !host) return false;
  try {
    const url = new URL(origin);
    return url.protocol === 'http:' &&
      ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) &&
      url.host === host;
  } catch { return false; }
}
