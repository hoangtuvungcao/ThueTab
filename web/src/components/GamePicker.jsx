import React, { useRef, useState } from 'react';
import { UploadCloud, FileCode, Clock } from 'lucide-react';
import { uploadJar, fileSize } from '../api.js';
import { useApp } from '../store.js';
import { GameIcon, KindBadge, JarBadge, useToast, Button } from './ui.jsx';

export const CUSTOM = 'custom-jar';
export const sameChoice = (a, b) => (a.game || null) === (b.game || null) && (a.game !== CUSTOM || a.jar === b.jar);

// Inline .jar upload used by the picker and the Jars page. Resolves to the new jar (or null).
// Android pickers grey out files whose MIME type is not listed: JARs are often x-java-archive or octet-stream.
export const JAR_ACCEPT = '.jar,application/java-archive,application/x-java-archive,application/octet-stream';

export function useJarUpload(onDone) {
  const { config, refresh } = useApp();
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const upload = async file => {
    if (!file) return null;
    // Phones may hand over a .jar as "game.jar.zip" or with no extension; the server checks the file itself.
    if (/\.(apk|exe|zip|rar|7z)$/i.test(file.name) && !/\.jar\.zip$/i.test(file.name)) { toast('Chỉ chấp nhận file .jar.', 'error'); return null; }
    if (file.size > config.jar_max_mb * 1048576) { toast(`File vượt quá ${config.jar_max_mb} MB.`, 'error'); return null; }
    setBusy(true);
    try {
      const { jar } = await uploadJar(file);
      toast(jar.status === 'approved' ? `Đã tải lên ${jar.filename}.` : `Đã tải lên ${jar.filename}. Đang chờ quản trị viên duyệt.`, 'success');
      await refresh();
      onDone?.(jar);
      return jar;
    } catch (e) {
      toast(e.message, 'error');
      return null;
    } finally { setBusy(false); }
  };
  return [upload, busy];
}

// Choice of what a tab runs: an enabled catalog game, or one of the user's own JARs.
export default function GamePicker({ value, onChange, jars, current, allowUpload = true, allowNone = false }) {
  const { config } = useApp();
  const input = useRef(null);
  const [upload, busy] = useJarUpload(j => j.status === 'approved' && onChange({ game: CUSTOM, jar: j.id }));
  const catalog = config.games.filter(g => g.id !== CUSTOM);
  const customOn = config.games.some(g => g.id === CUSTOM && g.enabled);
  const isCur = c => current && sameChoice(c, current);
  const Opt = ({ choice, disabled, icon, title, sub, badge, hint }) => {
    const on = sameChoice(choice, value);
    return (
      <button type="button" role="radio" aria-checked={on} disabled={disabled} title={hint}
        className={'game-option' + (on ? ' on' : '')} onClick={() => onChange(choice)}>
        {icon}
        <span><strong>{title}</strong><small>{sub}</small></span>
        {isCur(choice) ? <span className="cur-tag">Đang chạy</span> : badge}
      </button>
    );
  };
  return (
    <div className="picker">
      {allowNone && (
        <div className="game-grid" role="radiogroup" aria-label="Chọn sau">
          <Opt choice={{ game: null, jar: null }} icon={<span className="jar-icon muted-icon"><Clock size={18} aria-hidden /></span>}
            title="Chọn game sau" sub="Chọn hoặc tải game lên sau" />
        </div>
      )}
      {customOn && (
        <div className="picker-group">
          <div className="picker-head">
            <span>File JAR của bạn</span>
            {allowUpload && <>
              <input ref={input} type="file" accept={JAR_ACCEPT} hidden onChange={e => { upload(e.target.files[0]); e.target.value = ''; }} />
              <Button size="sm" icon={UploadCloud} loading={busy} onClick={() => input.current.click()}>Tải JAR mới</Button>
            </>}
          </div>
          {jars.length === 0 ? (
            <p className="picker-empty"><FileCode size={16} aria-hidden /> Chưa có file nào. Tải lên game J2ME hoặc Java PC (.jar, tối đa {config.jar_max_mb} MB).</p>
          ) : (
            <div className="game-grid" role="radiogroup" aria-label="File JAR">
              {jars.map(j => (
                <Opt key={j.id} choice={{ game: CUSTOM, jar: j.id }} disabled={j.status !== 'approved'}
                  icon={<span className="jar-icon"><FileCode size={18} aria-hidden /></span>}
                  title={j.filename} sub={fileSize(j.file_size)}
                  badge={j.status === 'approved' ? <KindBadge kind={j.kind} /> : <JarBadge status={j.status} />} />
              ))}
            </div>
          )}
        </div>
      )}
      {catalog.length > 0 && <div className="picker-group">
        <div className="picker-head"><span>Game có sẵn</span></div>
        <div className="game-grid" role="radiogroup" aria-label="Game có sẵn">
          {catalog.map(g => (
            <Opt key={g.id} choice={{ game: g.id, jar: null }} hint={g.description} icon={<GameIcon game={g} size={32} />} title={g.name} sub={g.kind} />
          ))}
        </div>
      </div>}
    </div>
  );
}
