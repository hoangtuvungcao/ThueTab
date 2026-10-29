from backend.stream import Hub, Viewer, is_keyframe

KEY = b'\x00\x00\x00\x01\x09\xf0\x00\x00\x00\x01\x67abc\x00\x00\x01\x65xyz'
DELTA = b'\x00\x00\x00\x01\x09\xf0\x00\x00\x00\x01\x41xyz'
JPEG = b'\xff\xd8\xff\xe0jpeg\xff\xd9'


def frames(v):
    out = []
    while not v.queue.empty(): out.append(v.queue.get_nowait())
    return out


def test_keyframe_detection():
    assert is_keyframe(KEY) and not is_keyframe(DELTA)


def test_video_viewer_joins_at_last_keyframe_and_codec_is_negotiated():
    hub = Hub()
    for f in (DELTA, KEY, DELTA, DELTA): hub.publish('t', f)
    v = Viewer(None, 30, 'h264')
    hub.add_viewer('t', v)
    assert frames(v) == [KEY, DELTA, DELTA]
    assert hub.video() == ['t']
    hub.add_viewer('t', Viewer(None, 30))  # a JPEG-only client (native app) switches the tab back to JPEG
    assert hub.video() == []


def test_video_viewer_resyncs_at_keyframe_when_behind():
    v = Viewer(None, 30, 'h264')
    v.offer(KEY)
    for _ in range(20): v.offer(DELTA)
    assert v.need_key and v.queue.empty()
    v.offer(DELTA)
    assert v.queue.empty()
    v.offer(KEY)
    assert frames(v) == [KEY]


def test_jpeg_still_reaches_thumbnails():
    hub = Hub()
    hub.publish('t', JPEG)
    assert hub.recent('t') == JPEG


def test_jpeg_viewer_never_gets_video_frames():
    hub = Hub()
    hub.publish('t', KEY)
    v = Viewer(None, 30)
    hub.add_viewer('t', v)
    hub.publish('t', DELTA)
    hub.publish('t', JPEG)
    assert frames(v) == [JPEG]


def test_ack_window_limits_frames_in_flight():
    import asyncio

    class WS:
        def __init__(self): self.sent = []
        async def send_bytes(self, b): self.sent.append(b)

    async def run():
        ws = WS()
        v = Viewer(ws, 30, 'mjpeg', ack=True)
        pump = asyncio.create_task(v.pump())
        for i in range(5):
            v.last_sent = 0
            v.offer(JPEG + bytes([i]))
            await asyncio.sleep(0)
        await asyncio.sleep(0.01)
        assert len(ws.sent) == 2          # window of 2 unacknowledged JPEG frames
        v.acked(); v.acked()
        await asyncio.sleep(0.01)
        assert len(ws.sent) == 3 and ws.sent[-1].endswith(bytes([4]))  # then only the newest frame
        pump.cancel()

    asyncio.run(run())
