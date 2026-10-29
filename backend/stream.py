"""In-memory relay for live game video (worker -> viewers) and low-latency input (viewers -> worker).

State lives in this process, so the API must run as a single uvicorn process (the default here).
"""
import asyncio, json, time

FPS_CHOICES = (30, 60)
THUMB_FPS = 2          # thumbnails (tab cards, wall) stream at a trickle while someone looks at them
THUMB_WINDOW = 20      # seconds a /frame request keeps the thumbnail stream alive
LOG_WINDOW = 60        # seconds a /logs request keeps log uploads going
MAX_VIEWERS_PER_TAB = 4


class Viewer:
    def __init__(self, ws, fps):
        self.ws = ws
        self.fps = fps
        self.queue = asyncio.Queue(maxsize=1)
        self.last_sent = 0.0

    def offer(self, frame):
        # Latest frame wins: a slow connection skips frames instead of building up delay.
        if time.monotonic() - self.last_sent < 0.9 / self.fps: return
        if self.queue.full():
            try: self.queue.get_nowait()
            except asyncio.QueueEmpty: pass
        self.queue.put_nowait(frame)

    async def pump(self):
        while True:
            frame = await self.queue.get()
            self.last_sent = time.monotonic()
            await self.ws.send_bytes(frame)


class Hub:
    def __init__(self):
        self.viewers = {}   # tab_id -> set[Viewer]
        self.workers = {}   # tab_id -> worker WebSocket
        self.latest = {}    # tab_id -> (jpeg bytes, monotonic time)
        self.thumb_seen = {}  # tab_id -> monotonic time of the last /frame request
        self.log_seen = {}    # tab_id -> monotonic time of the last /logs request

    def watch(self):
        """Tabs to stream and at what rate: live viewers' highest fps, else a thumbnail trickle.
        Nothing is captured for tabs nobody looks at."""
        # Called from the heartbeat thread: iterate over snapshots.
        t = time.monotonic()
        out = {tab: THUMB_FPS for tab, seen in list(self.thumb_seen.items()) if t - seen < THUMB_WINDOW}
        out.update({tab: max(v.fps for v in list(vs)) for tab, vs in list(self.viewers.items()) if vs})
        return out

    def logs_wanted(self):
        t = time.monotonic()
        return [tab for tab, seen in list(self.log_seen.items()) if t - seen < LOG_WINDOW]

    def add_viewer(self, tab, viewer):
        group = self.viewers.setdefault(tab, set())
        if len(group) >= MAX_VIEWERS_PER_TAB: return False
        group.add(viewer)
        if tab in self.latest: viewer.offer(self.latest[tab][0])
        return True

    def remove_viewer(self, tab, viewer):
        group = self.viewers.get(tab, set())
        group.discard(viewer)
        if not group: self.viewers.pop(tab, None)

    def publish(self, tab, frame):
        self.latest[tab] = (frame, time.monotonic())
        for v in list(self.viewers.get(tab, ())): v.offer(frame)

    def recent(self, tab, max_age=5):
        item = self.latest.get(tab)
        return item[0] if item and time.monotonic() - item[1] < max_age else None

    async def forward(self, tab, message):
        """Send input straight to the worker's stream connection; False if none is open."""
        ws = self.workers.get(tab)
        if not ws: return False
        try: await ws.send_text(json.dumps(message))
        except Exception: return False
        return True


hub = Hub()
