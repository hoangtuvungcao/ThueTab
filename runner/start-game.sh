#!/bin/sh
set -eu
mkdir -p /tmp/home
# SCREEN_W/SCREEN_H: the game's screen size (portrait or landscape), chosen per tab.
W="${SCREEN_W:-240}"
H="${SCREEN_H:-320}"
if [ "${GAME_KIND:-jar}" = "midp" ]; then
  # Just big enough for the emulator window: 21px menu bar above the game, status bar below. 16-bit colour
  # matches J2ME phones and halves framebuffer memory.
  XW="$W"; XH="$((H + 60))"; DEPTH=16
else
  XW=640; XH=480; DEPTH=24
fi
Xvfb :99 -screen 0 "${XW}x${XH}x${DEPTH}" -nolisten tcp -nocursor 2>/dev/null &
XVFB_PID=$!
trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT TERM INT
sleep 1
# Small-footprint JVM: serial GC, client compiler only, capped heap/metaspace/code cache.
JAVA_OPTS="-Xms16m -Xmx128m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -XX:CICompilerCount=1 -Xss256k
  -XX:MaxMetaspaceSize=64m -XX:ReservedCodeCacheSize=24m -XX:ActiveProcessorCount=1
  -Djava.io.tmpdir=/tmp -Duser.home=/tmp/home"
# The game runs at lower priority: many J2ME games busy-loop and would take the whole CPU allowance, starving the
# screen capture/encoder (live view drops to a few fps). Niced, the game still gets every cycle the encoder leaves.
# GAME_KIND/MIDLET_CLASS come from the API, which reads the JAR manifest at upload time.
if [ "${GAME_KIND:-jar}" = "midp" ]; then
  EMU=/opt/emu
  DEV=/tmp/device/thuetab
  mkdir -p "$DEV"
  sed -e "s/__W__/$W/g" -e "s/__H__/$H/g" -e "s/__PH__/$((H - 32))/g" -e "s/__SY__/$((H - 17))/g" \
      -e "s/__S2X__/$((W - 70))/g" -e "s/__UPX__/$((W / 2 - 10))/g" -e "s/__DNX__/$((W / 2))/g" -e "s/__ICY__/$((H - 14))/g" \
      /opt/emu/device-template.xml > "$DEV/device.xml"
  cp /opt/emu/normal.png "$DEV/normal.png"
  CP="$EMU/microemulator.jar:$EMU/nokiaui.jar:$EMU/jsr135.jar:/tmp/device"
  DEVICE=thuetab/device.xml
  if [ -n "${MIDLET_CLASS:-}" ]; then
    exec nice -n 10 java $JAVA_OPTS -cp "$CP" org.microemu.app.Main --device "$DEVICE" --appclasspath /opt/game/game.jar "$MIDLET_CLASS"
  fi
  exec nice -n 10 java $JAVA_OPTS -cp "$CP" org.microemu.app.Main --device "$DEVICE" /opt/game/game.jar
fi
exec nice -n 10 java $JAVA_OPTS -jar /opt/game/game.jar
