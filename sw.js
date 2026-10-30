/**
 * Service Worker: SE MANAGEMENT JOB - Mine Operations
 * Versi Cache: se-mine-ops-v55
 * Fitur: Offline Caching, Network-First untuk Halaman Utama (Navigation), Stale-While-Revalidate untuk aset statis
 */

const CACHE_NAME = 'se-mine-ops-v56';

// Daftar aset statis utama yang dicache saat instalasi
const PRECACHE_ASSETS = [
  './',
  './index.html',
  './xlsx.full.min.js',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-maskable-192.png',
  './icon-maskable-512.png',
  './apple-touch-icon.png'
];

// 1. EVENT INSTALL: Pre-cache aset inti & lewati antrean
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[SW] Pre-caching file inti offline...');
      return Promise.allSettled(
        PRECACHE_ASSETS.map((url) =>
          cache.add(url).catch((err) => {
            console.warn('[SW] Gagal meng-cache resource saat install:', url, err);
          })
        )
      );
    }).then(() => {
      console.log('[SW] Service Worker v1.0.9 berhasil diinstal.');
      return self.skipWaiting();
    })
  );
});

// 2. EVENT ACTIVATE: Bersihkan cache versi lama & ambil alih kontrol client
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            console.log('[SW] Menghapus cache versi lama:', cache);
            return caches.delete(cache);
          }
        })
      );
    }).then(() => {
      console.log('[SW] Service Worker v1.0.9 aktif dan mengontrol halaman.');
      return self.clients.claim();
    })
  );
});

// 3. EVENT FETCH: Tangani request offline/online
self.addEventListener('fetch', (event) => {
  const request = event.request;

  // Hanya tangani HTTP / HTTPS GET request
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Abaikan request ke skema selain http/https (misal chrome-extension://)
  if (!url.protocol.startsWith('http')) return;

  // DILARANG KERAS intercept API Supabase, Google Apps Script, Google Drive, atau request dinamis!
  // Biarkan browser mengeksekusinya langsung melalui jaringan asli (Network Direct)
  if (
    url.hostname.includes('supabase.co') ||
    url.hostname.includes('script.google.com') ||
    url.hostname.includes('googleusercontent.com') ||
    url.hostname.includes('drive.google.com') ||
    url.pathname.includes('/rest/v1/') ||
    url.pathname.includes('/auth/v1/') ||
    url.pathname.includes('/realtime/v1/')
  ) {
    return;
  }

  // PRIORITAS UTAMA: Request navigasi (HTML / buka halaman) menggunakan strategi NETWORK-FIRST
  // Agar saat ada pembaruan di GitHub/Server, browser langsung menampilkan kode terbaru
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((networkResponse) => {
          // Jangan cache jika respons adalah redirect untuk mencegah 'Cache.put() encountered a network error'
          if (networkResponse && networkResponse.status === 200 && !networkResponse.redirected) {
            const responseToCache = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(request, responseToCache).catch((err) => {
                console.warn('[SW] Gagal simpan cache navigasi:', err);
              });
            });
          }
          return networkResponse;
        })
        .catch(() => {
          // Jika pengguna sedang offline, baru sajikan dari cache
          return caches.match('./index.html') || caches.match('./');
        })
    );
    return;
  }

  // Untuk aset statis (gambar, font, css, js), gunakan Cache-First dengan background revalidate
  event.respondWith(
    caches.match(request).then((cachedResponse) => {
      if (cachedResponse) {
        // Ambil update dari network di background untuk request selanjutnya (Stale-While-Revalidate)
        fetch(request).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200 && !networkResponse.redirected) {
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(request, networkResponse.clone()).catch(() => { });
            });
          }
        }).catch(() => { });
        return cachedResponse;
      }

      // Jika belum ada di cache, ambil dari network dan simpan ke cache
      return fetch(request).then((networkResponse) => {
        if (!networkResponse || networkResponse.status !== 200 || networkResponse.type === 'opaque' || networkResponse.redirected) {
          return networkResponse;
        }

        const responseToCache = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(request, responseToCache).catch(() => { });
        });

        return networkResponse;
      }).catch((error) => {
        // Jangan melempar error tak tertangani ke konsol browser
        return new Response('', { status: 408, statusText: 'Request Offline or Aborted' });
      });
    })
  );
});

// 4. EVENT MESSAGE: Mendukung perintah pembaruan segera
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
