# Sửa máy tính AI — chạy thử nội bộ

Không cần tài khoản, API key hay tiền thật. Dùng một máy thử Windows 11 x64, màn hình mở khóa, có loa mặc định. Chạy máy chủ thử Mecha Server **trên cùng máy** theo hướng dẫn của repo máy chủ. Không mở cổng thử ra mạng.

1. Chuẩn bị công cụ và mã Flutter/Rust theo hướng dẫn build Mecha Windows của repository, rồi truyền thêm `--dart-define=MECHA_AI_REPAIR_DEMO=true` vào lệnh `flutter build windows`. Nếu API dùng cổng khác, truyền `--dart-define=MECHA_AI_REPAIR_URL=http://127.0.0.1:8000` với cổng đã chọn. Bản build thông thường không hiện mục Sửa máy tính AI.
2. Kết thúc mọi phiên điều khiển từ xa và dừng dịch vụ Mecha Remote từ trang chủ. Mở “Sửa máy tính AI”, đọc thông báo rồi chọn “Mở phiên thử”.
3. Tạo nạp ví giả, chọn “Giả lập chuyển khoản”. Không chuyển khoản bằng ứng dụng ngân hàng. Để thử âm thanh, tắt tiếng loa mặc định đang để âm lượng khoảng 20% và gửi “Loa bị tắt tiếng”.
4. Chấp nhận báo giá thử rồi xác nhận riêng việc đọc, bật tiếng và đọc kiểm tra. Bấm “Tôi đã nghe được” để chốt ví giả, hoặc “Vẫn chưa nghe được” để nhả giữ.
5. Thử “Dừng ngay”, “Ổ C gần đầy” và “Máy in không hoạt động”. Máy in chỉ có thống kê và bản xem trước giả; bước gửi chỉ gửi mã kiểm tra, không gửi ảnh hoặc nhật ký thật.

Cửa sổ đồng ý dùng thông điệp phần cứng tại console, không dùng kênh điều khiển chuột/phím của RustDesk. Nếu đã đổi âm thanh rồi dừng, khôi phục bằng Cài đặt > Hệ thống > Âm thanh; bản thử không tự hoàn tác. Token ví thử chỉ nằm trong bộ nhớ khi trang đang mở. Không dùng bản thử trên máy chứa dữ liệu quan trọng.

Kiểm thử giả lập trong thư mục `flutter/`: `flutter test test/repair_demo_test.dart`. Test này không kiểm chứng loa vật lý, phiên RDP, khóa màn hình hoặc tính chất nguồn đầu vào của thiết bị/driver Windows.
