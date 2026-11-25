# Nghiệm thu Mecha Remote v0.1.0-beta

- Tên hiển thị: **Mecha Remote**. Mã gói Android: `com.mecha.remote`. Màu chính: `#146451`.
- Đã dựng và mở ứng dụng Linux x86_64 trên Ubuntu 22.04.5. [Màn hình chính](docs/anh/01-man-hinh-chinh.png) cho thấy tên, icon, màu Mecha và ID 3–3–3; mật khẩu một lần đã được che.
- Bản Linux dùng mock localhost hiển thị [lỗi mã hết hạn](docs/anh/02-ban-quyen-het-han.png) và [gói Pro với hạn dùng](docs/anh/03-ban-quyen-kich-hoat.png). Bản Linux không dùng mock vẫn giữ URL HTTPS ví dụ trong cấu hình.
- Kiểm thử Flutter cho định dạng ID, giấy phép, tên cửa sổ Linux và menu thiết bị: `+13: All tests passed!`. Chưa kiểm thử trực tiếp trên thiết bị Android hoặc máy Windows.
- Quy trình dựng Windows x64 và Android ARM64/universal: xem [GitHub Actions](https://github.com/ngnam202095-rgb/mecha-remote/actions/workflows/branded-app.yml).
- Chưa kiểm thử kết nối đầu cuối: máy chủ ID `id.example.vn` và chuyển tiếp `relay.example.vn` chỉ là tên miền tạm, chưa có VPS. API bản quyền thật cũng chưa được triển khai; chỉ dùng API mô phỏng để kiểm tra luồng kích hoạt.
- Xem [ghi chú bản beta](docs/v0.1.0-beta.md) về chữ ký và các giới hạn.
