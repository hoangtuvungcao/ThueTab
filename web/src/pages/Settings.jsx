import React from 'react';
import { Check } from 'lucide-react';
import { ACCENTS, NAV, USER_MENU, STREAM } from '../tokens.js';
import { useApp } from '../store.js';
import { Card, PageHead, Segmented, Switch } from '../components/ui.jsx';
import { ScreenPicker } from '../components/ScreenPicker.jsx';

// One labelled preference row: text on the left, control on the right (stacks on phones).
const Row = ({ label, desc, children }) => (
  <div className="pref-row">
    <div className="pref-text"><span className="pref-label">{label}</span>{desc && <small className="muted">{desc}</small>}</div>
    <div className="pref-control">{children}</div>
  </div>
);

export default function Settings() {
  const { prefs, setPref, config, user } = useApp();
  const pages = [...NAV, ...USER_MENU].filter(n => n.id !== 'settings' && (!n.admin || user.role === 'admin') && n.id !== 'admin');
  const seg = (key, options, label) => <Segmented label={label} value={prefs[key]} onChange={v => setPref(key, v)} options={options} />;
  return (
    <>
      <PageHead title="Cài đặt" desc="Tuỳ chỉnh giao diện và cách chơi. Cài đặt được đồng bộ giữa web và ứng dụng." />

      <Card title="Giao diện" className="prefs-card">
        <Row label="Chủ đề" desc="Tự động theo thiết bị hoặc chọn sáng/tối.">
          {seg('theme', [['dark', 'Tối'], ['light', 'Sáng'], ['system', 'Theo máy']], 'Chủ đề')}
        </Row>
        <Row label="Màu nhấn" desc="Màu của nút chính, viền và điểm nhấn.">
          <div className="swatches" role="radiogroup" aria-label="Màu nhấn">
            {Object.entries(ACCENTS).map(([id, a]) => (
              <button key={id} type="button" role="radio" aria-checked={prefs.accent === id} title={a.label} aria-label={a.label}
                className={'swatch' + (prefs.accent === id ? ' on' : '')} style={{ background: `linear-gradient(135deg,${a.accent},${a.accent_2})` }}
                onClick={() => setPref('accent', id)}>{prefs.accent === id && <Check size={16} aria-hidden />}</button>
            ))}
          </div>
        </Row>
        <Row label="Cỡ chữ" desc="Phóng to hoặc thu nhỏ toàn bộ chữ.">
          {seg('font_scale', [[90, '90%'], [100, '100%'], [110, '110%'], [125, '125%']], 'Cỡ chữ')}
        </Row>
        <Row label="Mật độ" desc="Thu gọn khoảng cách để thấy nhiều nội dung hơn.">
          {seg('density', [['comfortable', 'Thoáng'], ['compact', 'Gọn']], 'Mật độ')}
        </Row>
        <Switch label="Giảm chuyển động" desc="Tắt hiệu ứng và chuyển cảnh." checked={prefs.reduce_motion} onChange={v => setPref('reduce_motion', v)} />
      </Card>

      <Card title="Màn chơi" className="prefs-card">
        <Row label="FPS mặc định" desc="Tốc độ khung hình khi mở màn chơi.">
          {seg('default_fps', STREAM.fps_choices.map(f => [f, `${f} FPS`]), 'FPS mặc định')}
        </Row>
        <Switch label="Hiện FPS và độ trễ" desc="Hiển thị chỉ số trên thanh màn chơi." checked={prefs.show_fps} onChange={v => setPref('show_fps', v)} />
        <Row label="Cỡ bàn phím" desc="Kích thước phím ảo trong màn chơi.">
          {seg('keypad_size', [['sm', 'Nhỏ'], ['md', 'Vừa'], ['lg', 'Lớn']], 'Cỡ bàn phím')}
        </Row>
        <Switch label="Rung khi bấm phím" desc="Trên điện thoại hỗ trợ rung." checked={prefs.haptics} onChange={v => setPref('haptics', v)} />
        <Switch label="Âm thanh phím" desc="Tiếng click ngắn khi bấm phím ảo." checked={prefs.sounds} onChange={v => setPref('sounds', v)} />
        <div className="pref-row stack-row">
          <div className="pref-text"><span className="pref-label">Màn hình mặc định khi thuê tab</span><small className="muted">Có thể đổi cho từng tab bất cứ lúc nào.</small></div>
          <ScreenPicker screens={config.screens} value={prefs.default_screen} onChange={v => setPref('default_screen', v)} />
        </div>
      </Card>

      <Card title="Điều hướng & nhắc nhở" className="prefs-card">
        <Row label="Trang mở đầu" desc="Trang hiện ra sau khi đăng nhập.">
          <select value={prefs.start_page} onChange={e => setPref('start_page', e.target.value)} aria-label="Trang mở đầu">
            {pages.map(n => <option key={n.id} value={n.id}>{n.label}</option>)}
          </select>
        </Row>
        <Row label="Số cột Đa màn hình" desc="Bố cục lưới khi xem nhiều tab.">
          {seg('wall_columns', [['auto', 'Tự động'], [2, '2'], [3, '3'], [4, '4']], 'Số cột')}
        </Row>
        <Row label="Nhắc sắp hết hạn" desc="Hiện cảnh báo trên thẻ tab trước khi hết hạn.">
          {seg('expiry_alert_hours', [[0, 'Tắt'], [6, '6 giờ'], [12, '12 giờ'], [24, '24 giờ'], [48, '48 giờ']], 'Nhắc sắp hết hạn')}
        </Row>
      </Card>
    </>
  );
}
