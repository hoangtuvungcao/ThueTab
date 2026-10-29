import javax.microedition.lcdui.*;
import javax.microedition.midlet.MIDlet;

// Minimal MIDlet used to check that the J2ME runtime starts and receives keys.
public class HelloMidlet extends MIDlet {
    protected void startApp() {
        Canvas c = new Canvas() {
            String last = "-";
            protected void paint(Graphics g) {
                g.setColor(0x0a0e17); g.fillRect(0, 0, getWidth(), getHeight());
                g.setColor(0x10b981); g.drawString("ThueTab J2ME OK", 10, 10, Graphics.TOP | Graphics.LEFT);
                g.setColor(0xeef2f8); g.drawString("Phim: " + last, 10, 40, Graphics.TOP | Graphics.LEFT);
                g.drawString("Man hinh: " + getWidth() + "x" + getHeight(), 10, 70, Graphics.TOP | Graphics.LEFT);
                g.setColor(0x7c5cff); g.drawRect(0, 0, getWidth() - 1, getHeight() - 1);
            }
            protected void keyPressed(int k) { last = getKeyName(k); repaint(); }
            protected void pointerPressed(int x, int y) { last = "cham " + x + "," + y; repaint(); }
        };
        c.setFullScreenMode(true);
        Display.getDisplay(this).setCurrent(c);
    }
    protected void pauseApp() {}
    protected void destroyApp(boolean u) {}
}
