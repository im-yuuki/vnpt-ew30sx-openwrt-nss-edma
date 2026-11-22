# OpenWrt cho VNPT iGate EW30SX

Firmware thử nghiệm cho **EW30SX MP02.1** (IPQ5018, 256 MiB RAM, 32 MiB
SPI-NOR). Thay đổi riêng cho EW30SX nằm trong `patches/`, không nằm trên
nhánh fork từ xa. CI luôn lấy tip mới của nhánh upstream `c3po-tag-8021q`
và cập nhật các feed mà upstream khai báo.

| Profile | Đầu ra | Dùng để |
|---|---|---|
| `nor` | Kernel FIT + rootfs SquashFS riêng | Chạy từ flash; có LuCI HTTPS, firewall, IPv4/IPv6, PPPoE và Wi-Fi hai băng tần. |
| `ram` | Initramfs FIT | Khởi động tạm qua UART/TFTP để chẩn đoán; **không ghi FIT này vào flash**. |

NOR beta trước refactor đã boot từ U-Boot gốc, truy cập được qua LAN và
nhận cả hai radio. Cấu hình mới chưa được thử trên thiết bị. NSS offload bật mặc định;
AP và WPS giữ như OpenWrt chuẩn (tắt, chưa có khóa).
Không có ảnh cài qua web gốc hay `sysupgrade`; không ép nâng cấp.
Xem [ghi chú phần cứng và giới hạn](docs/ew30sx-ram-boot.md).

## Build qua GitHub Actions

Trên nhánh mặc định, mở **Actions → Build EW30SX firmware + signed APK
feeds → Run workflow**. Mỗi profile có artifact riêng với firmware,
SHA-256, kernel config, danh sách gói thực tế và APK feed đã ký.
Hai profile dùng cùng một commit OpenWrt; artifact ghi lại commit và
phiên bản các feed thực tế. Sau khi cả hai build thành công trên nhánh
mặc định, CI ghi lại commit upstream vào gitlink. Nếu patch xung đột
hoặc cấu hình bắt buộc bị mất, build dừng thay vì bỏ qua.
`publish_release` tạo prerelease chứa cả hai profile. `publish_pages` cần
đặt nguồn Pages là **GitHub Actions** trong Settings; mỗi lần deploy chỉ
giữ feed của lượt đó. Có thể đặt biến `EW30SX_PAGES_URL` nếu dùng tên
miền tùy chỉnh. Không trộn APK/kmod giữa các lượt build hoặc profile.

## Build cục bộ

Trong **bản clone mới** của repo, dùng toolchain host Linux gốc (ưu tiên
Fedora nếu đã có đủ [phụ thuộc OpenWrt][prereqs]). Chạy cho một profile
mỗi checkout để không trộn output hoặc khóa ký:

```bash
git submodule update --init -- openwrt-nss-edma
for patch in "$PWD"/patches/*.patch; do
    git -C openwrt-nss-edma apply --index "$patch" || exit
done
bash .github/ci/configure.sh nor
cd openwrt-nss-edma
make download -j"$(nproc)"
make -j"$(nproc)"
make package/index
bash ../.github/ci/collect.sh nor ../out/nor
```

Thay `nor` bằng `ram` cho bản RAM. Lệnh trên dùng commit lưu trong
gitlink; thêm `--remote` vào `git submodule update` nếu muốn dùng tip
upstream như CI.

[prereqs]: https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
