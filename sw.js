/**
 * Service Worker: SE MANAGEMENT JOB - Mine Operations
 * Versi Cache: se-mine-ops-v1.0.0
 * Fitur: Offline Caching, Stale-While-Revalidate untuk aset statis, Cache-First untuk Core Files
 */

const CACHE_NAME = 'se-mine-ops-v1.0.1';

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
      // addAll secara bertahap agar kegagalan 1 CDN tidak memblokir instalasi offline file lokal
      return Promise.allSettled(
        PRECACHE_ASSETS.map((url) =>
          cache.add(url).catch((err) => {
            console.warn('[SW] Gagal meng-cache resource saat install:', url, err);
          })
        )
      );
    }).then(() => {
      console.log('[SW] Service Worker berhasil diinstal.');
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
      console.log('[SW] Service Worker aktif dan mengontrol halaman.');
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

  // Strategi Cache-First dengan Network Fallback untuk aset lokal & library CDN
  event.respondWith(
    caches.match(request).then((cachedResponse) => {
      if (cachedResponse) {
        // Ambil update dari network di background untuk request selanjutnya (Stale-While-Revalidate)
        fetch(request).then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            caches.open(CACHE_NAME).then((cache) => cache.put(request, networkResponse.clone()));
          }
        }).catch(() => {
          // Tetap gunakan cachedResponse jika offline
        });
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
        // Fallback jika network offline dan bukan di cache
        if (request.mode === 'navigate') {
          return caches.match('./index.html');
        }
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
