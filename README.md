# เซียน Reversi (iOS)

ผู้ช่วยเล่น Reversi ใน WePlay: อ่านกระดานจากการบันทึกหน้าจอ แล้วบอกช่องที่ควรลงในหน้าต่างลอย (Picture in Picture)

- `App/` แอปหลัก: AI (Engine.swift), หน้าต่างลอย (PiPManager.swift), รับข้อมูลกระดาน (Receiver.swift)
- `Broadcast/` ส่วนบันทึกหน้าจอ: อ่านกระดาน (BoardReader.swift) แล้วส่งให้แอปผ่าน UDP localhost
- GitHub Actions สร้าง `SianReversi.ipa` (ไม่ได้เซ็น) ทุกครั้งที่ push แล้วแนบไว้ในหน้า Releases

ติดตั้ง: ดาวน์โหลด IPA จาก Releases → เปิด Sideloadly บน Windows → เสียบ iPhone → ลากไฟล์ใส่ → ใส่ Apple ID → Start
