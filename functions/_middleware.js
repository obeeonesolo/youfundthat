// Protection dev — à retirer avant ouverture publique du site.
const DEV_PASSWORD = 'yft-dev-2026';

export async function onRequest({ request, next }) {
  const auth = request.headers.get('Authorization') ?? '';
  const [scheme, encoded] = auth.split(' ');

  if (scheme === 'Basic' && encoded) {
    const [, pwd] = atob(encoded).split(':');
    if (pwd === DEV_PASSWORD) return next();
  }

  return new Response('Environnement de développement — accès restreint.', {
    status: 401,
    headers: {
      'WWW-Authenticate': 'Basic realm="YouFundThat Dev"',
      'Content-Type': 'text/plain;charset=UTF-8',
    },
  });
}
