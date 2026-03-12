#!/usr/bin/env python3
################################################################################
#  文件名称 : buddy_allocator.py
#  作者名称 : Joe Jiang
#  创建日期 : 2024/08/02
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  08/02     Joe Jiang   初始化版本
################################################################################
class BuddyAllocator:
    def __init__(self, size, min_alloc=1, reserve_addr_sz=None):
        self.size = size
        self.min_alloc = min_alloc

        self.free_lists = [[] for x in range((self.size-1).bit_length())]
        self.free_lists.append([0])
        self.allocations = {}
        if reserve_addr_sz != None:
            for sz in reserve_addr_sz:
                self.alloc(sz)

    def alloc(self, size):
        if size < 1 or size > self.size:
            raise ValueError("size({}) out of range".format(size))
        size = max(size, self.min_alloc)

        bucket = (size-1).bit_length()
        orig_bucket = bucket

        while bucket < len(self.free_lists):
            if not self.free_lists[bucket]:
                # find free block
                bucket += 1
                continue

            while bucket > orig_bucket:
                # split block
                block = self.free_lists[bucket].pop(0)
                bucket -= 1
                self.free_lists[bucket].append(block)
                self.free_lists[bucket].append(block+2**bucket)

            if self.free_lists[bucket]:
                # allocate
                block = self.free_lists[bucket].pop(0)
                self.allocations[block] = bucket
                return block

            break

        raise Exception("out of memory")

    def free(self, addr):
        if addr not in self.allocations:
            raise ValueError("unknown allocation")

        bucket = self.allocations.pop(addr)

        while bucket < len(self.free_lists):
            size = 2**bucket

            # find buddy
            if (addr // size) % 2:
                buddy = addr - size
            else:
                buddy = addr + size

            if buddy in self.free_lists[bucket]:
                # buddy is free, merge
                self.free_lists[bucket].remove(buddy)
                addr = min(addr, buddy)
                bucket += 1
            else:
                # buddy is not free, so add to free list
                self.free_lists[bucket].append(addr)
                return

        raise Exception("failed to free memory")
