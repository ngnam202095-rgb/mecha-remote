# Quyết định của KHỐI B

| Hạng mục | Quyết định |
|---|---|
| Nền tảng | RustDesk 1.5.3, commit `95cca3f661f635b3cc85c04935fe8d96d8f432ef`. Phạm vi giao diện mới: Flutter Windows/Android và bản chạy thử Linux. Giữ tên API, JNI, gói Dart và tên thư viện nội bộ để không phá công cụ dựng. |
| Thương hiệu | `branding.json` quản lý tên **Mecha Remote**, mã gói `com.mecha.remote`, màu rêu `#146451` và bộ nhận diện do chủ sản phẩm cung cấp. Giữ `Mecha` cho định danh nội bộ như tên dịch vụ và IPC; tên hiển thị là `Mecha Remote`. |
| Kết nối | ID tự sinh ngẫu nhiên trong khoảng 100.000.000–999.999.999; màn hình nhóm ba chữ số. Không cắt ID dài của hệ thống cũ vì sẽ đổi địa chỉ kết nối; không thu hồi ID cũ. Các endpoint và khóa công khai trong zip chỉ là ví dụ. |
| Quản trị | Tùy chọn lúc dựng `show_server_settings` mặc định tắt; cấp bản nội bộ có tùy chọn này bật cho quản trị viên. Không thay vai trò của quyền hệ điều hành hoặc xác thực máy chủ. |
| Bản quyền | API riêng với thời gian chờ 8 giây, không tự gọi khi bắt đầu kết nối từ xa. Dùng mã thiết bị ổn định của RustDesk và tên máy; Android gửi tên chung “Android”. Lưu kết quả kích hoạt ở cấu hình cục bộ của ứng dụng để hiển thị lại, không ghi mã vào log ứng dụng. Không dùng kết quả này làm chứng thực phân quyền máy chủ. Tệp cấu hình cục bộ không phải kho mã hóa bí mật; chỉ thử bằng mã giả. |
| Danh bạ | Danh bạ riêng trên thiết bị, không cần tài khoản hoặc máy chủ RustDesk Pro. Khi hết hạn, không xóa mục đã lưu; áp lại giới hạn khi thêm. Danh bạ đồng bộ, giới hạn số máy và quyền trả phí quan trọng thuộc khối C, không giả lập thực thi ở client. |
| Giá | Ghi đúng bảng PHẦN CHUNG trong cấu hình tham khảo; ứng dụng không thu tiền và không hiển thị giá cố định trong luồng kích hoạt. |
| Chưa có dữ liệu | Khóa công khai và địa chỉ thật của hạ tầng, thông tin pháp lý, tài khoản ngân hàng, chính sách: **[cần bổ sung]**. |
| Bàn giao | Nhập bản v2 vào kho công khai của chủ sản phẩm. Cây nguồn chứa trực tiếp `libs/hbb_common` đã sửa, để bản tải mã nguồn tại mỗi thẻ có đủ phần sửa đổi. Không dùng khóa ký trả phí hoặc đăng ký dịch vụ trả phí. |
