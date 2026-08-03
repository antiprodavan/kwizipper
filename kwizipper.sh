#!/bin/bash
# KWI pack/unpack — без sudo, symlink'и сохраняются
#   ./kwizipper.sh unpack <kwi> [dir]
#   ./kwizipper.sh pack   <dir> <kwi_out>
set -e

HDR_SIZE() { python3 -c "
with open('$1','rb') as d:
    f=d.read(0x200000)
for o in range(0x400,len(f)):
    if f[o:o+2]==b'\x53\xef':
        s=o-0x38
        if s>=0:
            i=int.from_bytes(f[s:s+4],'little')
            b=int.from_bytes(f[s+4:s+8],'little')
            if 0<i<10**7 and 0<b<10**8:
                print(s-0x400); exit(0)
print(0)
"; }

CMD="${1:-help}"

case "$CMD" in
unpack)
    KWI="${2:-LOADING.KWI}"
    DIR="${3:-kwi_files}"

    HS=$(HDR_SIZE "$KWI")
    [ "$HS" -eq 0 ] && echo "Не KWI: $KWI" && exit 1

    # Сохраняем заголовок для pack
    dd if="$KWI" of="$DIR.header" bs=$HS count=1 2>/dev/null
    echo "$HS" > "$DIR.header_size"

    # Извлекаем ext2 в tmp
    IMG="/tmp/kwi_ext2_$$.img"
    dd if="$KWI" of="$IMG" bs=$HS skip=1 2>/dev/null

    # Выгружаем файлы через debugfs (без sudo)
    rm -rf "$DIR"
    mkdir -p "$DIR"
    /usr/sbin/debugfs -R "rdump / \"$DIR\"" "$IMG" 2>&1 | grep -v "changing ownership" || true
    rm -f "$IMG"

    echo "✅ $DIR ($(du -sh $DIR 2>/dev/null | cut -f1))"
    ;;

pack)
    DIR="${2:-kwi_files}"
    KWI_OUT="${3:-LOADING_NEW.KWI}"

    [ ! -f "$DIR.header" ] && echo "Нет $DIR.header — запусти unpack сначала" && exit 1
    [ ! -f "$DIR.header_size" ] && echo "Нет $DIR.header_size" && exit 1

    HS=$(cat "$DIR.header_size")
    echo "Заголовок: $HS байт"
    echo "Файлы: $(du -sh $DIR 2>/dev/null | cut -f1)"

    # Создаём ext2 из директории
    IMG="/tmp/kwi_ext2_$$.img"
    DIRSIZE=$(( $(du -sb "$DIR" | cut -f1) + 104857600 ))  # +100MB запас
    truncate -s $DIRSIZE "$IMG"
    mkfs.ext2 -q -F -d "$DIR" "$IMG" 2>/dev/null

    # Ужимаем до минимума
    /usr/sbin/e2fsck -fy "$IMG" 2>/dev/null
    /usr/sbin/resize2fs -M "$IMG" 2>/dev/null

    # Склеиваем заголовок + ext2
    cat "$DIR.header" "$IMG" > "$KWI_OUT"
    rm -f "$IMG"
    echo "✅ $KWI_OUT ($(du -h $KWI_OUT | cut -f1))"
    ;;

*)
    echo "KWI pack/unpack (без sudo)"
    echo "  $0 unpack <kwi> [dir]   KWI → директория"
    echo "  $0 pack   <dir> <out>   директория → KWI"
    echo
    echo "Пример:"
    echo "  $0 unpack LOADING.KWI my_files"
    echo "  (меняешь файлы в my_files/)"
    echo "  $0 pack   my_files LOADING_NEW.KWI"
    ;;
esac
