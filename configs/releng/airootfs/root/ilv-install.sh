#!/usr/bin/env bash
set -euo pipefail

cleanup() {
    [[ -n "${ILV_TMPFILE:-}" ]] && rm -f -- "$ILV_TMPFILE"
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && { echo "Cần quyền root"; exit 1; }

# Kiểm tra các công cụ cần thiết
for cmd in jq archinstall reflector ping; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd không được cài đặt"; exit 1; }
done

echo "Đang tối ưu hóa tốc độ tải..."
reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
    echo "Không có internet! Vui lòng dùng 'nmtui' để kết nối trước."
    exit 1
fi

# Tìm ổ đĩa mục tiêu (thứ tự ưu tiên)
if [ -b "/dev/nvme0n1" ]; then
    TARGET_DISK="/dev/nvme0n1"
elif [ -b "/dev/vda" ]; then
    TARGET_DISK="/dev/vda"
elif [ -b "/dev/sda" ]; then
    TARGET_DISK="/dev/sda"
else
    echo "Không tìm thấy ổ đĩa phù hợp!"
    exit 1
fi

echo "Đã phát hiện ổ đĩa mục tiêu: $TARGET_DISK"
read -p "Nhập username: " input_user
while [[ -z "${input_user}" ]]; do
    echo "Username không được để trống."
    read -p "Nhập username: " input_user
done

read -s -p "Nhập mật khẩu: " input_pass
echo ""
while [[ -z "${input_pass}" ]]; do
    echo "Mật khẩu không được để trống."
    read -s -p "Nhập mật khẩu: " input_pass
    echo ""
done

# Tìm file cấu hình (giả sử cùng thư mục với script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/ilv_config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Không tìm thấy $CONFIG_FILE"
    unset input_pass
    exit 1
fi

# Tạo file tạm an toàn
ILV_TMPFILE="$(mktemp /tmp/ilv_config_tmp.XXXXXX.json)"
chmod 600 "$ILV_TMPFILE"

# Cập nhật cấu hình: cập nhật disk và user vào array
if ! jq --arg disk "$TARGET_DISK" --arg user "$input_user" --arg pass "$input_pass" \
    '.disk_layouts[0].device = $disk
     | .wipe = true
     | .users[0].username = $user
     | .users[0].password = $pass
     | .users[0].sudo = true' \
    "$CONFIG_FILE" > "$ILV_TMPFILE"; then
    echo "Lỗi khi cập nhật cấu hình với jq."
    unset input_pass
    exit 1
fi

# Xóa biến chứa mật khẩu trong shell
unset input_pass

echo "Đang khởi chạy cài đặt trên $TARGET_DISK..."
set +e
archinstall --config "$ILV_TMPFILE"
INSTALL_STATUS=$?
set -e

if [ $INSTALL_STATUS -eq 0 ]; then
    echo "Cài đặt thành công."
    touch /etc/ilv_installed
else
    echo "Cài đặt thất bại (Mã: $INSTALL_STATUS)."
    exit $INSTALL_STATUS
fi
