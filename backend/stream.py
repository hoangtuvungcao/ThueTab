"""In-memory relay for live game video (worker -> viewers) and low-latency input (viewers -> worker).

State lives in this process, so the API must run as a single uvicorn process (the default here).
"""
import asyncio, json, time

FPS_CHOICES = (30, 60)
THUMB_FPS = 2          # thumbnails (tab cards, wall) stream at a trickle while someone looks at them
THUMB_WINDOW = 20      # seconds a /frame request keeps the thumbnail stream alive
LOG_WINDOW = 60        # seconds a /logs request keeps log uploads going
MAX_VIEWERS_PER_TAB = 4


def is_jpeg(frame):
    return frame[:2] == b'\xff\xd8'


def is_keyframe(au):
    """H.264 access unit (Annex B) that starts a decodable picture: contains SPS (7) or an IDR slice (5)."""
    i = au.find(b'\x00\x00\x01')
    while i >= 0 and i + 3 < len(au):
        if au[i + 3] & 0x1f in (5, 7): return True
        i = au.find(b'\x00\x00\x01', i + 3)
    return False


class Viewer:
    def __init__(self, ws, fps, codec='mjpeg', ack=False):
        self.ws = ws
        self.fps = fps
        self.codec = codec  # 'h264' if the client decodes video (WebCodecs), else 'mjpeg'
        self.queue = asyncio.Queue()
        self.last_sent = 0.0
        self.need_key = True
        # Flow control: clients that acknowledge each frame ({"type":"ack"}) never have more than a few frames
        # in flight. Without it a slow uplink fills the proxy/tunnel buffers with seconds of frames, and inputs,
        # fps changes and pongs queue behind them.
        self.ack = ack
        # Rate the tab actually streams at: the highest fps among its viewers. A viewer that chose 30 still
        # receives a 60 fps stream when someone else watches at 60, so its flow-control window and backlog
        # limit must follow the stream, not its own choice (it would keep dropping to keyframes: ~15 fps).
        self.rate = fps
        self.inflight = 0
        self.room = asyncio.Event()
        self.room.set()

    def window(self):
        # JPEG: 2 frames in flight (frames can be skipped). Video: ~0.35 s of the stream.
        return 2 if self.codec != 'h264' else max(6, self.rate * 35 // 100)

    def acked(self):
        self.inflight = max(0, self.inflight - 1)
        if self.inflight < self.window(): self.room.set()

    def offer(self, frame):
        if is_jpeg(frame):
            # Latest frame wins: a slow connection skips frames instead of building up delay.
            if time.monotonic() - self.last_sent < 0.9 / self.fps: return
            while not self.queue.empty(): self.queue.get_nowait()
            self.queue.put_nowait(frame)
            return
        # JPEG-only clients (native app, old browsers) can't decode video: while the tab switches codec they
        # wait for the first JPEG instead of getting undecodable frames.
        if self.codec != 'h264': return
        # Video frames depend on the previous ones, so they can't be skipped one by one: when the link falls more
        # than ~0.5 s behind, drop the backlog and resume at the next keyframe (one per second).
        key = is_keyframe(frame)
        if self.queue.qsize() > self.rate // 2:
            while not self.queue.empty(): self.queue.get_nowait()
            self.need_key = True
        if self.need_key and not key: return
        self.need_key = False
        self.queue.put_nowait(frame)

    async def pump(self):
        while True:
            if self.ack:
                await self.room.wait()
            frame = await self.queue.get()
            self.last_sent = time.monotonic()
            if self.ack:
                self.inflight += 1
                if self.inflight >= self.window(): self.room.clear()
            await self.ws.send_bytes(frame)


class Hub:
    def __init__(self):
        self.viewers = {}   # tab_id -> set[Viewer]
        self.workers = {}   # tab_id -> worker WebSocket
        self.latest = {}    # tab_id -> (jpeg bytes, monotonic time)
        self.gop = {}       # tab_id -> H.264 frames since the last keyframe (lets a new viewer start instantly)
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

    def video(self):
        """Tabs whose viewers all decode H.264; the others (native app, older browsers) get JPEG."""
        return [tab for tab, vs in list(self.viewers.items()) if vs and all(v.codec == 'h264' for v in list(vs))]

    def logs_wanted(self):
        t = time.monotonic()
        return [tab for tab, seen in list(self.log_seen.items()) if t - seen < LOG_WINDOW]

    def add_viewer(self, tab, viewer):
        group = self.viewers.setdefault(tab, set())
        if len(group) >= MAX_VIEWERS_PER_TAB: return False
        group.add(viewer)
        self.retune(tab)
        if viewer.codec == 'h264' and self.gop.get(tab):
            for f in self.gop[tab]: viewer.offer(f)
        elif tab in self.latest: viewer.offer(self.latest[tab][0])
        return True

    def remove_viewer(self, tab, viewer):
        group = self.viewers.get(tab, set())
        group.discard(viewer)
        self.retune(tab)
        if not group:
            self.viewers.pop(tab, None)
            self.gop.pop(tab, None)

    def retune(self, tab):
        """Call when viewers join/leave or change fps: every viewer follows the tab's stream rate."""
        group = self.viewers.get(tab, ())
        rate = max((v.fps for v in group), default=30)
        for v in group:
            v.rate = rate
            if v.inflight < v.window(): v.room.set()

    def publish(self, tab, frame):
        if is_jpeg(frame):
            self.latest[tab] = (frame, time.monotonic())
            self.gop.pop(tab, None)
        elif is_keyframe(frame): self.gop[tab] = [frame]
        elif tab in self.gop and len(self.gop[tab]) < 240: self.gop[tab].append(frame)
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
