#!/bin/bash
set -e
[[ $EUID -ne 0 ]] && { echo "Cần quyền root"; exit 1; }
echo "Đang tối ưu hóa tốc độ tải..."
reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Không có internet! Vui lòng dùng 'nmtui' để kết nối trước."
    exit 1
fi

echo "Đang khởi động tiến trình cài đặt tự động ILV-LINUX..."
archinstall --config /root/ilv_config.json

if [ $? -eq 0 ]; then
    touch /etc/ilv_installed
    echo "Cài đặt thành công! File flag đã được tạo."
fi

echo "------------------------------------------"
echo "Cài đặt xong! Hãy khởi động lại máy."
echo "------------------------------------------"
