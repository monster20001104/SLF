#!/usr/bin/env python3
################################################################################
#  文件名称 : utils.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/02
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/02     Joe Jiang   初始化版本
################################################################################
def hexdump_line(data, offset, row_size=16):
    h = ""
    c = ""
    for ch in data[0:row_size]:
        h += f"{ch:02x} "
        c += chr(ch) if 32 < ch < 127 else "."
    return f"{offset:08x}: {h:{row_size*3}} {c}"


def hexdump(data, start=0, length=None, row_size=16, prefix="", offset=0):
    stop = min(start+length, len(data)) if length else len(data)
    for k in range(start, stop, row_size):
        print(prefix+hexdump_line(data[k:min(k+row_size, stop)], k+offset, row_size))


def hexdump_lines(data, start=0, length=None, row_size=16, prefix="", offset=0):
    lines = []
    stop = min(start+length, len(data)) if length else len(data)
    for k in range(start, stop, row_size):
        lines.append(prefix+hexdump_line(data[k:min(k+row_size, stop)], k+offset, row_size))
    return lines


def hexdump_str(data, start=0, length=None, row_size=16, prefix="", offset=0):
    return "\n".join(hexdump_lines(data, start, length, row_size, prefix, offset))