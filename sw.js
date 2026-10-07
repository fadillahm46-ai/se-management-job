/**
 * Service Worker: SE MANAGEMENT JOB - Mine Operations
 * Versi Cache: se-mine-ops-v1.0.6
 * Fitur: Offline Caching, Network-First untuk Halaman Utama (Navigation), Stale-While-Revalidate untuk aset statis
 */

const CACHE_NAME = 'se-mine-ops-v1.0.6';

// Daftar aset statis utama yang dicache saat instalasi
const PRECACHE_ASSETS = [
  './',
  './index.html',
  './xlsx.full.min.js',
  './TEMPLATE_ROSTER_SE_MANAGEMENT.xlsx',
  './TEMPLATE_DATA_MASTER_ARMADA.xlsx',
  './TEMPLATE_POPULASI_UNIT_SE_MANAGEMENT.xlsx',
  './TEMPLATE_NO_OPT_PRODUKSI_SE_MANAGEMENT.xlsx',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon.svg',
  'https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap',
  'https://cdn.tailwindcss.com',
  'https://cdn.jsdelivr.net/npm/chart.js',
  'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://lh3.googleusercontent.com/d/1wwl4IRJggVH1EBW54ANXb2Mi3dnUejEU',
  'https://lh3.googleusercontent.com/d/1HdWJm4xe7WoW7rkbBfZN_T6YRT2Er86F',
  'https://lh3.googleusercontent.com/d/1kTftX1-eoOfOYWaB8ZhjwyNLxG7-_uDY'
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
      console.log('[SW] Service Worker v1.0.2 berhasil diinstal.');
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
      console.log('[SW] Service Worker v1.0.2 aktif dan mengontrol halaman.');
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

  // PRIORITAS UTAMA: Request navigasi (HTML / buka halaman) menggunakan strategi NETWORK-FIRST
  // Agar saat ada pembaruan di GitHub/Server, browser langsung menampilkan kode terbaru
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseToCache = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, responseToCache));
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
          if (networkResponse && networkResponse.status === 200) {
            caches.open(CACHE_NAME).then((cache) => cache.put(request, networkResponse.clone()));
          }
        }).catch(() => {});
        return cachedResponse;
      }

      // Jika belum ada di cache, ambil dari network dan simpan ke cache
      return fetch(request).then((networkResponse) => {
        if (!networkResponse || networkResponse.status !== 200 || networkResponse.type === 'opaque') {
          return networkResponse;
        }

        const responseToCache = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(request, responseToCache);
        });

        return networkResponse;
      }).catch((error) => {
        throw error;
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
