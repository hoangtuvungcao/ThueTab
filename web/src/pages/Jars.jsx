import React, { useRef, useState } from 'react';
import { UploadCloud, FileCode, Trash2, Play, ShieldCheck } from 'lucide-react';
import { api, fileSize, dateTime } from '../api.js';
import { navLabel } from '../tokens.js';
import { useApp } from '../store.js';
import { Button, Card, Empty, JarBadge, PageHead, Alert, Modal, KindBadge, Skeleton, MAINT_HINT, Confirm } from '../components/ui.jsx';
import { useJarUpload } from '../components/GamePicker.jsx';
import { Pager, usePaged } from '../components/DataTable.jsx';

export default function Jars() {
  const { jars, config, act, open, tabs, loaded, maint } = useApp();
  const input = useRef(null);
  const [drag, setDrag] = useState(false);
  const [del, setDel] = useState(null);
  const paged = usePaged(jars || []);
  const autoApprove = config.jar_auto_approve !== false; // field may be absent on older servers

  const [upload, busy] = useJarUpload();

  return (
    <>
      <PageHead title={navLabel('jars')} desc="Tải lên game .jar của bạn (J2ME hoặc Java PC), rồi chọn cho tab bất cứ lúc nào." />
      <Card>
        <div className={'dropzone' + (drag ? ' on' : '')}
          onDragOver={e => { e.preventDefault(); setDrag(true); }} onDragLeave={() => setDrag(false)}
          onDrop={e => { e.preventDefault(); setDrag(false); if (!maint) upload(e.dataTransfer.files[0]); }}>
          <UploadCloud size={28} aria-hidden />
          <div>
            <strong>Kéo thả file .jar vào đây</strong>
            <p className="muted">Tối đa {config.jar_max_mb} MB · J2ME hoặc Java PC · tự nhận loại game</p>
          </div>
          <input ref={input} type="file" accept=".jar,application/java-archive" hidden onChange={e => { upload(e.target.files[0]); e.target.value = ''; }} />
          <Button variant="primary" icon={UploadCloud} loading={busy} disabled={maint} title={maint ? MAINT_HINT : undefined} onClick={() => input.current.click()}>Chọn file</Button>
        </div>
        <Alert kind="info" icon={ShieldCheck}>
          {autoApprove
            ? 'File dùng được ngay sau khi tải lên và chạy tách biệt cho từng tab. File vi phạm điều khoản có thể bị chặn.'
            : 'Mỗi file được kiểm tra trước khi chạy. Chỉ file "Đã duyệt" mới chọn được cho tab.'}
        </Alert>
      </Card>

      <Card title={`File của bạn (${jars.length})`} pad={false}>
        {!loaded ? <div className="card-pad"><Skeleton variant="rows" count={2} /></div> : jars.length === 0 ? (
          <Empty icon={FileCode} title="Chưa có file JAR nào">Tải lên file .jar để chạy bản game riêng trong tab.</Empty>
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Tên file</th><th>Trạng thái</th><th className="hide-mobile">Tải lên</th><th className="right">Thao tác</th></tr></thead>
              <tbody>
                {paged.rows.map(j => (
                  <tr key={j.id}>
                    <td><span className="row gap-sm min0"><strong className="ellipsis" title={j.filename}>{j.filename}</strong><KindBadge kind={j.kind} /></span>
                      <small className="muted">{fileSize(j.file_size)}</small></td>
                    <td><JarBadge status={j.status} /></td>
                    <td className="hide-mobile">{dateTime(j.created)}</td>
                    <td className="right">
                      <div className="row gap-xs end">
                        {j.status === 'approved' && <Button size="sm" icon={Play} onClick={() => open('rent', { jarId: j.id })}>Thuê tab</Button>}
                        <Button size="sm" variant="ghost" icon={Trash2} aria-label={`Xóa ${j.filename}`} title="Xóa file" onClick={() => setDel(j)} />
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <Pager {...paged.pager} unit="file" />
          </div>
        )}
      </Card>

      {del && (
        <Confirm title={`Xóa "${del.filename}"?`} danger confirmLabel="Xóa file" onClose={() => setDel(null)}
          onConfirm={() => act(() => api('/jars/' + del.id, 'DELETE'), 'Đã xóa file JAR.')}>
          {(tabs || []).some(t => t.custom_jar_id === del.id)
            ? `File đang được tab "${tabs.find(t => t.custom_jar_id === del.id).name}" sử dụng — hãy đổi game của tab đó trước.`
            : 'File sẽ bị xóa vĩnh viễn.'}
        </Confirm>
      )}
    </>
  );
}
