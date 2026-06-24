#!/bin/bash
set -e
[[ $EUID -ne 0 ]] && { echo "Cần quyền root"; exit 1; }
echo "Đang tối ưu hóa tốc độ tải..."
reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Không có internet! Vui lòng dùng 'nmtui' để kết nối trước."
    exit 1
fi
read -p "Nhập username: " input_user
read -s -p "Nhập mật khẩu: " input_pass
echo ""
jq --arg user "$input_user" --arg pass "$input_pass" \
   '.users[0].username = $user | .users[0].password = $pass' \
   ilv_config.json > ilv_config_tmp.json
   
echo "Đang khởi tạo cấu hình..."
echo "Đang khởi động tiến trình cài đặt tự động ILV-LINUX..."
archinstall --config ilv_config_tmp.json
if [ $? -eq 0 ]; then
    touch /etc/ilv_installed
    echo "Cài đặt thành công! File flag đã được tạo."
fi
rm ilv_config_tmp.json
echo "------------------------------------------"
echo "Cài đặt xong! Hãy khởi động lại máy."
echo "------------------------------------------"
