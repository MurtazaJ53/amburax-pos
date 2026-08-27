// A service worker whose only job is to remove itself.
//
// Something in this browser registered one against this origin, and it asks
// for /sw.js on every navigation - a 404 in the log each time. Nothing in
// this app registers a service worker, so it is a leftover: an earlier
// version of the site, a tool, or a different app that once ran on this port.
//
// A 404 leaves the old worker registered and in charge, and that is the part
// worth caring about. A stale service worker can keep serving pages out of
// its own cache, so somebody sees an old version of a screen after a deploy
// and no amount of reloading changes it. It is among the hardest bugs to
// recognise, because everything else says the new code shipped.
//
// So rather than let the 404 stand, this answers with a worker that empties
// every cache it owns and unregisters. The next navigation has no service
// worker at all, which is the intended state.

self.addEventListener("install", () => {
  // Do not wait for the old worker to finish: replacing it now is the point.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      // Everything this origin cached, whoever put it there.
      const names = await caches.keys();
      await Promise.all(names.map((name) => caches.delete(name)));

      await self.registration.unregister();

      // Reload any page still controlled by the old worker so it comes from
      // the network rather than from the cache just deleted.
      const clients = await self.clients.matchAll({ type: "window" });
      for (const client of clients) {
        client.navigate(client.url);
      }
    })(),
  );
});

// Deliberately no fetch handler. A worker that intercepts requests is exactly
// what causes this problem; this one must never sit between page and network.
