#!/usr/bin/env python3
################################################################################
#  文件名称 : sparse_memory.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/09/11
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  09/11     Joe Jiang   初始化版本
################################################################################
from utils import hexdump, hexdump_lines, hexdump_str


class SparseMemory:
    def __init__(self, size):
        self.size = size
        self.segs = {}

    def read(self, address, length, **kwargs):
        if address < 0 or address >= self.size:
            raise ValueError("address out of range")
        if length < 0:
            raise ValueError("invalid length")
        if address+length > self.size:
            raise ValueError("operation out of range")
        data = bytearray()
        while length > 0:
            block_offset = address & 0xfff
            block_addr = address - block_offset
            block_len = min(4096 - block_offset, length)
            try:
                block = self.segs[block_addr]
            except KeyError:
                block = b'\x00'*4096
            data.extend(block[block_offset:block_offset+block_len])
            address += block_len
            length -= block_len
        return bytes(data)

    def write(self, address, data, **kwargs):
        if address < 0 or address >= self.size:
            raise ValueError("address out of range")
        if address+len(data) > self.size:
            raise ValueError("operation out of range")
        offset = 0
        length = len(data)
        while length > 0:
            block_offset = address & 0xfff
            block_addr = address - block_offset
            block_len = min(4096 - block_offset, length)
            try:
                block = self.segs[block_addr]
            except KeyError:
                block = bytearray(4096)
                self.segs[block_addr] = block
            block[block_offset:block_offset+block_len] = data[offset:offset+block_len]
            address += block_len
            offset += block_len
            length -= block_len

    def clear(self):
        self.segs.clear()

    def hexdump(self, address, length, prefix=""):
        hexdump(self.read(address, length), prefix=prefix, offset=address)

    def hexdump_lines(self, address, length, prefix=""):
        return hexdump_lines(self.read(address, length), prefix=prefix, offset=address)

    def hexdump_str(self, address, length, prefix=""):
        return hexdump_str(self.read(address, length), prefix=prefix, offset=address)

    def __len__(self):
        return self.size

    def __getitem__(self, key):
        if isinstance(key, int):
            return self.read(key, 1)[0]
        elif isinstance(key, slice):
            start, stop, step = key.indices(self.size)
            if step == 1:
                return self.read(start, stop-start)
            else:
                raise IndexError("specified step size is not supported")

    def __setitem__(self, key, value):
        if isinstance(key, int):
            self.write(key, [value])
        elif isinstance(key, slice):
            start, stop, step = key.indices(self.size)
            if step == 1:
                value = bytes(value)
                if stop-start != len(value):
                    raise IndexError("slice assignment is wrong size")
                return self.write(start, value)
            else:
                raise IndexError("specified step size is not supported")