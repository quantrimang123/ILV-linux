#!/bin/bash
set -e
cleanup() {
    rm -f ilv_config_tmp.json
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && { echo "Cần quyền root"; exit 1; }

command -v jq &> /dev/null || { echo "jq không được cài đặt"; exit 1; }
command -v archinstall &> /dev/null || { echo "archinstall không được cài đặt"; exit 1; }

echo "Đang tối ưu hóa tốc độ tải..."
reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Không có internet! Vui lòng dùng 'nmtui' để kết nối trước."
    exit 1
fi

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
read -s -p "Nhập mật khẩu: " input_pass
echo ""

jq --arg disk "$TARGET_DISK" \
   --arg user "$input_user" \
   --arg pass "$input_pass" \
   '.disk_layouts[0].device = $disk | .users[0].username = $user | .users[0].password = $pass' \
   ilv_config.json > ilv_config_tmp.json

chmod 600 ilv_config_tmp.json

echo "Đang khởi chạy cài đặt trên $TARGET_DISK..."
set +e
archinstall --config ilv_config_tmp.json
INSTALL_STATUS=$?
set -e

if [ $INSTALL_STATUS -eq 0 ]; then
    echo "Cài đặt thành công."
    touch /etc/ilv_installed
else
    echo "Cài đặt thất bại (Mã: $INSTALL_STATUS)."
    exit $INSTALL_STATUS
fi
