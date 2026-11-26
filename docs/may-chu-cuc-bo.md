# Kết nối Mecha Remote với máy chủ cục bộ

Dựng hệ thống thử bằng `docker compose up` theo README của `mecha-server`. Từ máy chạy Compose, kiểm tra `http://localhost:8080/health` trả `{"ok":true}` và lấy **khóa công khai của máy thử**:

```bash
docker compose exec -T hbbs cat /root/id_ed25519.pub
```

Không sao chép tệp `id_ed25519` (khóa riêng). Trong bản dựng nội bộ, đặt `show_server_settings` thành `true` trong `branding.json` và chạy lệnh sau trước khi dựng để **Cài đặt → Bản quyền** dùng API cục bộ:

```bash
python3 apply-branding.py --license-api http://localhost:8080
```

Trong ứng dụng, mở **Cài đặt → Mạng → Máy chủ ID và chuyển tiếp**, nhập và lưu:

| Trường | Giá trị trên máy chạy Docker |
| --- | --- |
| Máy chủ ID | `127.0.0.1:21116` |
| Máy chủ chuyển tiếp | `127.0.0.1:21117` |
| Máy chủ API | `http://localhost:8080` |
| Khóa | Nội dung `id_ed25519.pub` vừa lấy |

Trường Máy chủ API trong hộp thoại Mạng không thay thế tùy chọn bản dựng `--license-api` cho mục **Bản quyền**. Tạo một đơn bằng web cục bộ, xác nhận bằng webhook thử rồi dùng mã ở **Cài đặt → Bản quyền**. Không chuyển tiền hoặc dùng mật khẩu thật.

Theo mặc định Compose chỉ lắng nghe trên loopback. Nếu thử điều khiển giữa hai máy được phép trên cùng mạng LAN, đặt `RUSTDESK_BIND` thành IP LAN của máy Docker và `RELAY_ADDRESS` thành IP đó kèm `:21117`; dùng IP LAN thay cho `127.0.0.1` ở hai trường ID/chuyển tiếp trên cả hai máy. Giữ cổng API cục bộ cho thử kích hoạt ở máy Docker; không mở dịch vụ ra Internet. Không dùng các tùy chỉnh cục bộ này trong bản phát hành.
