# Mecha Remote

Bản thử nghiệm tiếng Việt của Mecha Remote, sửa đổi từ [RustDesk 1.5.3](https://github.com/rustdesk/rustdesk/tree/1.5.3), bản quyền © Purslane Tech Pte. Ltd. và các tác giả đóng góp. Giữ nguyên [giấy phép GNU AGPL-3.0](LICENCE). Xem [nghiệm thu](NGHIEM-THU.md), [quyết định](QUYET-DINH.md) và [cách cung cấp mã nguồn](AGPL.md).

## 1. Chuẩn bị mã nguồn

1. Sao chép kho công khai [ngnam202095-rgb/mecha-remote](https://github.com/ngnam202095-rgb/mecha-remote). Mã nguồn `libs/hbb_common` đã được đưa trực tiếp vào kho, dựa trên commit `fae47e024dd83cef6aaecde0aa7d11731df11649` của upstream, có áp cấu hình Mecha.
2. Cài Python 3.10+ và ImageMagick (`magick` hoặc `convert` trên PATH).
3. Sửa **`branding.json`** để đổi tên, mã gói, màu, máy chủ, khóa công khai, API hoặc nguồn. Bộ nhận diện gồm PNG nguồn 1024×1024 cho icon và hai SVG logo Mecha Remote cho giao diện sáng/tối. Nếu đổi màu thương hiệu, cập nhật cả các tệp nhận diện.
4. Tại thư mục gốc, chạy `python3 apply-branding.py` (Windows: `python apply-branding.py`). Không sửa tay các tệp sinh từ cấu hình. Giữ mã thư viện/JNI nội bộ theo upstream.
5. XML và ứng dụng giữ các mục cài đặt kết nối, ngôn ngữ và quyền chia sẻ màn hình gốc. Để hiện lại mục **Máy chủ ID và chuyển tiếp**, chỉ trong bản nội bộ đổi `show_server_settings` thành `true` rồi áp dụng cấu hình và dựng lại. Đây không phải cơ chế phân quyền.

Các máy chủ và khóa kèm trong bản thử **không dùng để kết nối thật**. Khi có hạ tầng, dùng cùng máy chủ ID/chuyển tiếp và khóa công khai trên hai máy. Mở ứng dụng ở cả hai đầu; người được hỗ trợ chia sẻ ID và mật khẩu một lần, người hỗ trợ nhập ID rồi chọn **Kết nối**. Không chia sẻ mật khẩu với người lạ.

## 2. Dựng Windows và Android trên GitHub Actions

1. Bật GitHub Actions và cho phép các action của bên thứ ba được ghim trong workflow `branded-app.yml`. Không cần khai báo bí mật ký số.
2. Workflow chạy khi đẩy lên `main` hoặc từ **Actions → Build and publish Mecha Remote beta → Run workflow**. Chạy trên nhánh chỉ tạo **Artifacts** để kiểm tra.
3. Để phát hành, chuẩn bị ghi chú `docs/<tag>.md` rồi đẩy thẻ `v*` (ví dụ `v0.1.0-beta`). Sau khi dựng thành công đủ ba gói, công việc xuất bản tạo pre-release bằng `GITHUB_TOKEN`.
4. Bộ cài Windows x64 chưa ký và phải giữ đuôi `-install.exe`. APK ARM64 và universal dùng khóa gỡ lỗi của CI, chỉ dùng thử. Xem [ghi chú beta](docs/v0.1.0-beta.md).

## 3. Thử API bản quyền và danh bạ

1. Tại thư mục gốc, chạy `python3 mock/license_server.py`. Mock chỉ lắng nghe trên `127.0.0.1:8765`; dữ liệu mất khi dừng.
2. Đối với bản dựng thử trên máy chạy mock, áp dụng `python3 apply-branding.py --license-api http://127.0.0.1:8765` trước khi dựng. Trên Android, dùng bản debug và chạy `adb reverse tcp:8765 tcp:8765` khi thiết bị đã kết nối ADB. Gỡ tùy chọn này và chạy lại script trước khi tạo gói phát hành.
3. Mở **Cài đặt → Bản quyền**, nhập `MECHA-DEMO-PRO`, chọn **Kích hoạt**, kiểm tra gói Pro và hạn dùng. Mở lại ứng dụng để kiểm tra trạng thái lưu; chọn **Gỡ kích hoạt máy này** để trả chỗ và về gói miễn phí.
4. Thử `MECHA-DEMO-FULL`, `MECHA-DEMO-EXPIRED`, một mã sai và dừng mock để xem thông báo tương ứng. Không cần kết nối máy chủ bản quyền để nhập ID và bắt đầu kết nối điều khiển.
5. Với gói miễn phí, mở tab **Danh bạ**, lưu năm ID thử có chín chữ số khác nhau; ID thứ sáu phải bị chặn và hiện lời mời nâng cấp. Bấm vào một mục để dùng luồng kết nối có sẵn, hoặc dùng nút xóa để nhường chỗ.
6. Có thể kiểm tra thành phần trong `flutter/`: dùng Flutter 3.24.5, chạy `flutter pub get`, sau đó `flutter test --no-pub test/brand_license_test.dart test/id_formatter_test.dart --reporter expanded`. Kiểm thử hợp đồng HTTP dùng mock localhost; kiểm thử giao diện thành phần dùng phản hồi mô phỏng.

## 4. Chạy hoặc dựng bản Linux

- Giải nén `khoi-b-linux-x86_64.tar.gz` và chạy `./khoi-b-linux-x86_64/rustdesk` trên desktop Linux x86_64. Bản thử xác minh trên Ubuntu 22.04.5, với các máy chủ ví dụ trong cấu hình.
- Để dựng lại, cài Flutter 3.24.5, áp dụng `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff` trong thư mục SDK Flutter và cài các phụ thuộc hệ thống theo [workflow gốc](.github/workflows/flutter-build.yml). Cài thêm `autoconf`, `automake` và `libtool` cho các port vcpkg nếu hệ thống chưa có.
- Lấy vcpkg ở commit `9e593bb18ea69cc5095e012465dcd675a822ed0d`, chạy `bootstrap-vcpkg.sh` và đặt `VCPKG_ROOT` trỏ tới thư mục đó. Tại gốc cây nguồn, chạy `"$VCPKG_ROOT/vcpkg" install --triplet x64-linux --x-install-root="$VCPKG_ROOT/installed"`.
- Sinh các tệp bridge theo [workflow bridge](.github/workflows/bridge.yml), sau đó áp dụng bước tương thích Linux của upstream: `python3 -c 'from build import ffi_bindgen_function_refactor; ffi_bindgen_function_refactor()'`.
- Tại gốc cây nguồn, chạy `cargo build --locked --release --lib --features flutter`. Trong `flutter/`, chạy `flutter pub get` và `flutter build linux --release --no-pub`; ứng dụng nằm tại `flutter/build/linux/x64/release/bundle/rustdesk` tính từ gốc cây nguồn.

Tên công ty, địa chỉ, hotline, mã số thuế, tài khoản ngân hàng, chính sách bảo mật và điều khoản: **[cần bổ sung]**.
