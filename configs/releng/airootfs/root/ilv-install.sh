#!/usr/bin/env bash
set -euo pipefail

cleanup() {
    [[ -n "${ILV_TMPFILE:-}" ]] && rm -f -- "$ILV_TMPFILE"
    [[ -n "${CONFIG_BACKUP:-}" ]] && [[ -f "$CONFIG_BACKUP" ]] && rm -f -- "$CONFIG_BACKUP"
}
trap cleanup EXIT

[[ $EUID -ne 0 ]] && { echo "Cần quyền root"; exit 1; }

# Kiểm tra các công cụ cần thiết
for cmd in jq archinstall reflector ping; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd không được cài đặt"; exit 1; }
done

# Kiểm tra /tmp writable và có không gian
if [[ ! -w /tmp ]]; then
    echo "Lỗi: /tmp không có quyền ghi!"
    exit 1
fi

TMP_SPACE=$(df /tmp | awk 'NR==2 {print $4}')
if [[ $TMP_SPACE -lt 102400 ]]; then
    echo "Lỗi: /tmp không có đủ không gian (cần ít nhất 100MB)!"
    exit 1
fi

echo "Đang tối ưu hóa tốc độ tải..."
if ! reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null; then
    echo "Cảnh báo: reflector thất bại, tiếp tục với mirror mặc định..."
fi

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

# Validate disk writable
if [[ ! -w "$TARGET_DISK" ]]; then
    echo "Lỗi: Không có quyền ghi trên $TARGET_DISK!"
    exit 1
fi

echo "Đã phát hiện ổ đĩa mục tiêu: $TARGET_DISK"
read -p "Nhập username: " input_user
while [[ -z "${input_user}" ]]; do
    echo "Username không được để trống."
    read -p "Nhập username: " input_user
done

# Validate username (bắt đầu bằng chữ cái hoặc _, 3-32 ký tự)
if ! [[ "$input_user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{2,31}$ ]]; then
    echo "Username phải từ 3-32 ký tự, bắt đầu bằng chữ cái hoặc _, chỉ chứa chữ cái, số, _, -"
    unset input_user
    exit 1
fi

read -s -p "Nhập mật khẩu: " input_pass
echo ""
while [[ -z "${input_pass}" ]]; do
    echo "Mật khẩu không được để trống."
    read -s -p "Nhập mật khẩu: " input_pass
    echo ""
done

# Validate mật khẩu (tối thiểu 8 ký tự)
if [[ ${#input_pass} -lt 8 ]]; then
    echo "Mật khẩu phải có tối thiểu 8 ký tự."
    unset input_pass
    exit 1
fi

# Tìm file cấu hình (giả sử cùng thư mục với script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/ilv_config.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Không tìm thấy $CONFIG_FILE"
    unset input_pass
    exit 1
fi

# Validate JSON của CONFIG_FILE
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo "Lỗi: $CONFIG_FILE không hợp lệ!"
    unset input_pass
    exit 1
fi

# Kiểm tra disk_layouts và users arrays không trống
if ! jq -e '.disk_layouts | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "Lỗi: disk_layouts array trống hoặc không tồn tại trong config!"
    unset input_pass
    exit 1
fi

if ! jq -e '.users | length > 0' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "Lỗi: users array trống hoặc không tồn tại trong config!"
    unset input_pass
    exit 1
fi

# Tạo file tạm an toàn
ILV_TMPFILE="$(mktemp /tmp/ilv_config_tmp.XXXXXX.json)"
chmod 600 "$ILV_TMPFILE"

# Tìm index của disk trong config
DISK_INDEX=$(jq --arg disk "$TARGET_DISK" '.disk_layouts | map(.device == $disk) | index(true)' "$CONFIG_FILE" 2>/dev/null || echo "null")

# Tìm index của user trong config
USER_INDEX=$(jq --arg user "$input_user" '.users | map(.username == $user) | index(true)' "$CONFIG_FILE" 2>/dev/null || echo "null")

# Nếu disk không tồn tại, sử dụng phần tử đầu tiên
if [ "$DISK_INDEX" == "null" ]; then
    DISK_INDEX=0
fi

# Nếu user không tồn tại, sử dụng phần tử đầu tiên
if [ "$USER_INDEX" == "null" ]; then
    USER_INDEX=0
fi

# Cập nhật cấu hình: cập nhật disk và user vào đúng vị trí trong array
if ! jq --arg disk "$TARGET_DISK" \
    --arg user "$input_user" \
    --argjson disk_idx "$DISK_INDEX" \
    --argjson user_idx "$USER_INDEX" \
    ".disk_layouts[\$disk_idx].device = \$disk
     | .disk_layouts[\$disk_idx].wipe = true
     | .users[\$user_idx].username = \$user
     | .users[\$user_idx].sudo = true" \
    "$CONFIG_FILE" > "$ILV_TMPFILE"; then
    echo "Lỗi khi cập nhật cấu hình với jq."
    rm -f "$ILV_TMPFILE"
    unset input_pass
    exit 1
fi

# Cập nhật mật khẩu vào file tạm (tránh truyền qua command line)
if ! jq --arg pass "$input_pass" '.users['"$USER_INDEX"'].password = $pass' "$ILV_TMPFILE" > "${ILV_TMPFILE}.tmp"; then
    echo "Lỗi khi cập nhật mật khẩu."
    rm -f "$ILV_TMPFILE" "${ILV_TMPFILE}.tmp"
    unset input_pass
    exit 1
fi
mv "${ILV_TMPFILE}.tmp" "$ILV_TMPFILE"

# Xóa biến chứa mật khẩu trong shell
unset input_pass

# Validate JSON output trước khi chạy archinstall
if ! jq empty "$ILV_TMPFILE" 2>/dev/null; then
    echo "Lỗi: File config không hợp lệ!"
    rm -f "$ILV_TMPFILE"
    exit 1
fi

# Kiểm tra file tạm có tồn tại
if [[ ! -f "$ILV_TMPFILE" ]] || [[ ! -s "$ILV_TMPFILE" ]]; then
    echo "Lỗi: File config tạm không được tạo hoặc trống!"
    exit 1
fi

# Lưu backup của config với permissions an toàn
CONFIG_BACKUP="/tmp/ilv_config_backup_$(date +%Y%m%d_%H%M%S).json"
cp "$ILV_TMPFILE" "$CONFIG_BACKUP"
chmod 600 "$CONFIG_BACKUP"
echo "Backup config: $CONFIG_BACKUP"

echo "Đang khởi chạy cài đặt trên $TARGET_DISK..."
set +e
archinstall --config "$ILV_TMPFILE"
INSTALL_STATUS=$?
set -e

if [ $INSTALL_STATUS -eq 0 ]; then
    echo "Cài đặt thành công."
    touch /etc/ilv_installed
    # Xóa backup file sau cài đặt thành công (vì chứa mật khẩu plaintext)
    rm -f "$CONFIG_BACKUP"
    echo "Backup config đã xóa (chứa mật khẩu)."
else
    echo "Cài đặt thất bại (Mã: $INSTALL_STATUS)."
    echo "Để debug, kiểm tra: $CONFIG_BACKUP"
    exit $INSTALL_STATUS
fi
