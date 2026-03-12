#!/usr/bin/env python3
################################################################################
#  文件名称 : virtio_defines.py
#  作者名称 : Joe Jiang
#  创建日期 : 2025/10/21
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  10/21     Joe Jiang   初始化版本
################################################################################
import sys
import random
import itertools
import math
sys.path.append('../common')
from stream_bus import define_stream
from backpressure_bus import define_backpressure
from address_space import MemoryRegion
from ram_tbl import define_ram_tbl
from scapy.all import Packet, BitField
import cocotb
from typing import List, NamedTuple, Union
from generate_eth_pkg import *

class VirtioBlkType:
    VIRTIO_BLK_T_IN            = 0
    VIRTIO_BLK_T_OUT           = 1 #write
    VIRTIO_BLK_T_FLUSH         = 4
    VIRTIO_BLK_T_DISCARD       = 11
    VIRTIO_BLK_T_WRITE_ZEROES  = 13

class Mbufs(NamedTuple):
    regs     : List  
    len      : int
    typ      : VirtioBlkType


class TestType:
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2

def _typ_map(typ):
    _map = {TestType.NETTX:"nettx", TestType.NETRX:"netrx", TestType.BLK:"blk"}
    return _map[typ]

def blk_type_map(typ):
    _map = {VirtioBlkType.VIRTIO_BLK_T_IN:"VIRTIO_BLK_T_IN",
            VirtioBlkType.VIRTIO_BLK_T_OUT:"VIRTIO_BLK_T_OUT",
            VirtioBlkType.VIRTIO_BLK_T_FLUSH:"VIRTIO_BLK_T_FLUSH",
            VirtioBlkType.VIRTIO_BLK_T_DISCARD:"VIRTIO_BLK_T_DISCARD",
            VirtioBlkType.VIRTIO_BLK_T_WRITE_ZEROES:"VIRTIO_BLK_T_WRITE_ZEROES"}
    return _map[typ]

class VirtioStatus:
    IDLE            = 0x1
    STARTING        = 0x2
    DOING           = 0x4
    STOPPING        = 0x8
    FORCED_SHUTDOWN = 0x10

def _status_map(typ):
    _map = {VirtioStatus.IDLE:"IDLE", VirtioStatus.STARTING:"STARTING", VirtioStatus.DOING:"DOING", VirtioStatus.STOPPING:"STOPPING"}
    return _map[typ]

def status_str(status):
    return _status_map(status)

def fake_urandom(n):
    return random.getrandbits(8 * n).to_bytes(n, 'big')

class VirtioCtrlRegOffset:
    BDF                             = 0x0
    DEV_ID                          = 0x8
    AVAIL_RING_ADDR                 = 0x10
    USED_RING_ADDR                  = 0x18
    DESC_ADDR                       = 0x20
    QSIZE                           = 0x28
    INDIRECT_SUPPORT                = 0x30
    MAX_LEN                         = 0x38
    GENERATION                      = 0x40
    CTRL                            = 0x48
    AVAIL_IDX                       = 0x50
    BLK_DS_PTR                      = 0x50
    BLK_UP_PTR                      = 0x50
    AVAIL_UI_PTR                    = 0x58
    AVAIL_PI_PTR                    = 0x58
    AVAIL_CI_PTR                    = 0x58
    USED_PTR                        = 0x58
    SOC_NOTIFY                      = 0x60
    IDX_ENGINE_RD_REQ_NUM           = 0x68
    IDX_ENGINE_RD_RSP_NUM           = 0x68
    USED_ERR_FATAL_FLAG             = 0x70
    USED_ELEM_PTR                   = 0x70
    ERR_INFO                        = 0x78
    MSIX_ADDR                       = 0x80
    MSIX_DATA                       = 0x88
    MSIX_ENABLE                     = 0x90
    MSIX_MASK                       = 0x98
    MSIX_PENDING                    = 0xa0
    MSIX_AGGREGATION_TIME           = 0xa8
    MSIX_AGGREGATION_THRESHOLD      = 0xb0
    IRQ_MERGE_INFO_UNIT0            = 0xb8
    IRQ_MERGE_INFO_UNIT1            = 0xb8
    IRQ_MERGE_INFO_UNIT2            = 0xb8
    IRQ_MERGE_INFO_UNIT3            = 0xb8
    IRQ_MERGE_INFO_UNIT4            = 0xc0
    IRQ_MERGE_INFO_UNIT5            = 0xc0
    IRQ_MERGE_INFO_UNIT6            = 0xc0
    IRQ_MERGE_INFO_UNIT7            = 0xc0
    QOS_ENABLE                      = 0x100
    QOS_L1_UNIT                     = 0x108
    QOS_L2_UNIT                     = 0x110
    NET_IDX_LIMIT                   = 0x130
    BLK_DESC_ENG_DESC_TBL_ADDR      = 0x150
    BLK_DESC_ENG_DESC_TBL_SIZE      = 0x158
    BLK_DESC_ENG_DESC_TBL_NEXT      = 0x160
    BLK_DESC_ENG_DESC_TBL_ID        = 0x160
    BLK_DESC_ENG_DESC_CNT           = 0x160
    BLK_DESC_ENG_DATA_LEN           = 0x168
    BLK_DESC_ENG_IS_INDIRCT         = 0x168
    BLK_DESC_ENG_RESUMER            = 0x168
    NET_DESC_ENGINE_HEAD_SLOT       = 0x180
    NET_DESC_ENGINE_HEAD_SLOT_VLD   = 0x180
    NET_DESC_ENGINE_TAIL_SLOT       = 0x180
    NET_RX_IDX_LIMIT                = 0x0
    NET_TX_IDX_LIMIT                = 0x8

class VirtqUsedElement(Packet):
    name = 'virtq_used_elem'
    fields_desc = [
        BitField("len",           0,  32),
        BitField("id",            0,  32)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")
    @classmethod
    def unpack(cls, data):
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        elif type(data) == bytes:
            return cls(data)
        else:
            raise ValueError("The {} type is not supported".format(type(data)))

class VirtqDesc(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("next",            0,  16),
        BitField("flags_rsv",       0,  13),
        BitField("flags_indirect",  0,   1),
        BitField("flags_write",     0,   1),
        BitField("flags_next",      0,   1),
        BitField("len",             0,  32),
        BitField("addr",            0,  64)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")
    @classmethod
    def unpack(cls, data):
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))

class VirtioVq(Packet):
    name = 'virtio_vq'
    fields_desc = [
        BitField("typ",             0,  2),
        BitField("qid",             0,  8)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")
    @classmethod
    def unpack(cls, data):
        if type(data) == cocotb.binary.BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))


class VirtqBlkReqHeader(Packet):
    name = 'virtq_blk_req_hdr'
    fields_desc = [
        BitField("reserved1",        0, 32*10),
        BitField("magic_num",        0, 16),    
        BitField("reserved",         0, 8),    
        BitField("ctrl",             0, 8), 
        BitField("host_buf_len",     0, 32),
        BitField("host_buf_addr",    0, 64),
        BitField("flags",            0, 16),
        BitField("desc_idx",         0, 16),   
        BitField("err_info",         0, 8),   
        BitField("vq_gen",           0, 8), 
        BitField("vq_gid",           0, 16)  
    ]

    width = 0
    for field in fields_desc:
        width += field.size
    padding_size = (8 - width % 8) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
        width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        if isinstance(data, cocotb.binary.BinaryValue):
            return cls(data.buff)
        if isinstance(data, int):
            return cls(data.to_bytes(len(cls()), "big"))
        if isinstance(data, bytes):
            return cls(data)
        raise ValueError(f"The {type(data)} type is not supported")

class VirtqBlkRspHeader(Packet):
    name = 'virtq_blk_rsp_hdr'
    fields_desc = [
        BitField("reserved1",        0, 32*10),
        BitField("magic_num",        0, 16),    
        BitField("used_idx",         0, 16),    
        BitField("used_len",         0, 32),
        BitField("host_buf_addr",    0, 64),
        BitField("flags",            0, 16),
        BitField("desc_idx",         0, 16),   
        BitField("reserved",         0, 8),   
        BitField("vq_gen",           0, 8), 
        BitField("vq_gid",           0, 16)  
    ]

    width = 0
    for field in fields_desc:
        width += field.size
    padding_size = (8 - width % 8) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
        width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        if isinstance(data, cocotb.binary.BinaryValue):
            return cls(data.buff)
        if isinstance(data, int):
            return cls(data.to_bytes(len(cls()), "big"))
        if isinstance(data, bytes):
            return cls(data)
        raise ValueError(f"The {type(data)} type is not supported")

def qid2vq(qid, typ):
    return VirtioVq(qid=qid, typ=typ).pack()

def vq2qid(vq):
    vq = VirtioVq().unpack(vq)
    return vq.qid, vq.typ

def vq_str(vq):
    vq = VirtioVq().unpack(vq)
    return f"(qid:{vq.qid},typ:{_typ_map(vq.typ)})"

DoorbellReqBus, _, DoorbellReqSource, _, _ = define_stream("doorbell_req",
    signals=["vq"], 
    optional_signals=None,
    vld_signal = "vld",
    rdy_signal = "rdy"
)

QosReqBus, QosReqTrans, QosReqMaster, QosReqSlaver, QosReqMoniter = define_stream(
    "qos_query_req",
    signals=["uid"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
QosRspBus, QosRspTrans, QosRspMaster, QosRspSlaver, QosRspMoniter = define_stream(
    "qos_query_rsp",
    signals=["ok"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
QosUpdateBus, QosUpdateTrans, QosUpdateMaster, QosUpdateSlaver, QosUpdateMoniter = define_stream(
    "qos_update",
    signals=["uid", "len", "pkt_num"],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

def gen_q_list(q_num):
    return random.sample(range(0, 255), q_num)

def randbit(y):
    assert y >= 0
    return random.randint(0, 2**y - 1)


def rand_norm_int(low=0, high=128, mu=64, sigma=20):
    if low == high:
        return low
    while True:
        x = random.gauss(mu, sigma)  # 生成正态分布
        if low <= x <= high:         # 超出范围则重抽（截断正态）
            return int(round(x))

class VirtioBlkOuthdr(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("sector",      0,  64),
        BitField("ioprio",      0,  32),
        BitField("type",        0,  32)
    ]
    width = 0
    for elemnt in fields_desc:
        width += elemnt.size
    padding_size = (8 - width) % 8
    if padding_size:
        fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
    width += padding_size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")
    @classmethod
    def unpack(cls, data):
        if isinstance(data, cocotb.binary.BinaryValue):
            return cls(data.buff)
        if isinstance(data, int):
            return cls(data.to_bytes(len(cls()), "big"))
        if isinstance(data, bytes):
            return cls(data)
        raise ValueError(f"The {type(data)} type is not supported")

def gen_hdr(id, op_type=None):
    sector = randbit(64)
    #默认是写
    header = VirtioBlkOuthdr(type=op_type, ioprio=id, sector=sector).build()[::-1]
    return header

async def gen_pkt(mem, bdf, dev_id, id, op_type, pld_data, pld_data_len, len_list):
    regs = []
    hdr_data = gen_hdr(id, op_type)
    hdr_reg = mem.alloc_region(16, bdf=bdf, dev_id=dev_id)
    regs.append(hdr_reg)
    await hdr_reg.write(0, hdr_data)
    if op_type == VirtioBlkType.VIRTIO_BLK_T_OUT:
        for length in len_list:
            pld_reg = mem.alloc_region(length, bdf=bdf, dev_id=dev_id)
            await pld_reg.write(0, pld_data[:length])
            pld_data = pld_data[length:]
            regs.append(pld_reg)
    elif op_type == VirtioBlkType.VIRTIO_BLK_T_IN:
        for length in len_list:
            pld_reg = mem.alloc_region(length, bdf=bdf, dev_id=dev_id)
            regs.append(pld_reg)
    else:
        pld_data_len = 0
    sts_reg = mem.alloc_region(1, bdf=bdf, dev_id=dev_id)
    regs.append(sts_reg)
    return Mbufs(regs, 17+pld_data_len, op_type)

class Cfg(NamedTuple):
    q_num                   : int
    max_seq                 : int
    dma_latency             : int
    max_len                 : int
    min_chain_num           : int
    max_chain_num           : int
    max_indirct_ptr         : int
    max_indirct_desc_size   : int
    qsz_width_list          : List
    qos_en                  : bool
    random_qos              : float
    msix_en                 : bool
    indirct_support         : bool
    indirct_relaxed_ordering: bool
    life_cycle_en           : bool
    force_shutdown_en       : bool

smoke_cfg = Cfg(
            q_num                   = 1,
            max_seq                 = 300,
            dma_latency             = 256,
            max_len                 = 1024,
            min_chain_num           = 256,
            max_chain_num           = 256,
            max_indirct_ptr         = 256,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [10],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = False,
            force_shutdown_en       = False
        )

test_1Q_short_chian_cfg = Cfg(
            q_num                   = 1,
            max_seq                 = 20000,
            dma_latency             = 512,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 8,
            max_indirct_ptr         = 8,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = False,
            force_shutdown_en       = False
        )

test_nQ_short_chian_cfg = Cfg(
            q_num                   = 8,
            max_seq                 = 20000,
            dma_latency             = 512,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 8,
            max_indirct_ptr         = 8,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 9, 10, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = False,
            force_shutdown_en       = False
        )


test_1Q_long_chian_cfg = Cfg(
            q_num                   = 1,
            max_seq                 = 2000,
            dma_latency             = 256,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 128,
            max_indirct_ptr         = 128,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = False,
            force_shutdown_en       = False
        )

test_nQ_long_chian_cfg = Cfg(
            q_num                   = 8,
            max_seq                 = 2000,
            dma_latency             = 256,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 2048,
            max_indirct_ptr         = 2048,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 9, 10, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = False,
            force_shutdown_en       = False
        )

test_1Q_life_cycle_cfg = Cfg(
            q_num                   = 1,
            max_seq                 = 20000,
            dma_latency             = 1024,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 16,
            max_indirct_ptr         = 16,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = True,
            force_shutdown_en       = False
        )

test_nQ_life_cycle_cfg = Cfg(
            q_num                   = 8,
            max_seq                 = 20000,
            dma_latency             = 1024,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 16,
            max_indirct_ptr         = 16,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 9, 10, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = True,
            force_shutdown_en       = False
        )

test_1Q_force_shutdown_cfg = Cfg(
            q_num                   = 1,
            max_seq                 = 20000,
            dma_latency             = 1024,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 16,
            max_indirct_ptr         = 16,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = True,
            force_shutdown_en       = True
        )

test_nQ_force_shutdown_cfg = Cfg(
            q_num                   = 8,
            max_seq                 = 20000,
            dma_latency             = 1024,
            max_len                 = 1024,
            min_chain_num           = 1,
            max_chain_num           = 16,
            max_indirct_ptr         = 16,
            max_indirct_desc_size   = (64*1024//16),
            qsz_width_list          = [8, 9, 9, 10, 10, 15],
            qos_en                  = True,
            random_qos              = 0.5,
            msix_en                 = True, # the init of msix_en
            indirct_support         = True,
            indirct_relaxed_ordering= True,
            life_cycle_en           = True,
            force_shutdown_en       = True
        )
