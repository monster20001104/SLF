import sys

sys.path.append('../../common')
import random
import itertools
from scapy.all import Packet, BitField
from cocotb.binary import BinaryValue
from typing import List, NamedTuple
from address_space import MemoryRegion
from backpressure_bus import define_backpressure
from stream_bus import define_stream
from ram_tbl import define_ram_tbl


class Config:
    def __init__(self, name="Config"):
        self._name = name
        self._data = {}
        # self._mode = None
        self._getmode = "error"

    def __setattr__(self, name, value):
        if name.startswith('_'):
            object.__setattr__(self, name, value)
        else:
            self._data[name] = value

    def __getattr__(self, name):
        if name.startswith('_'):
            return object.__getattribute__(self, name)
        if name not in self._data and self._getmode == "error":
            raise AttributeError(f"'{self._name}'has no'{name}'")
        return self._data.get(name)

    def __delattr__(self, name):
        try:
            del self._data[name]
        except KeyError:
            raise AttributeError(f"'{self._name}'对象无属性'{name}'")

    def update(self, other):
        if not isinstance(getattr(other, '_data', None), dict):
            raise TypeError("需传入包含字典类型_data属性的对象")
        self._data.update(other._data.copy())

    def __str__(self):
        return self._to_string()

    def _to_string(self, indent=0):
        prefix = '    ' * indent
        if indent == 0:
            result = [f"{prefix}{self._name}:"]
        else:
            result = []
        for key, value in self._data.items():
            if isinstance(value, Config):
                result.append(f"{prefix}    {key}_{value._name}")
                result.append(value._to_string(indent + 1))
            else:
                result.append(f"{prefix}    {key}: {value}")
        return '\n'.join(result)


class VirtqDesc(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("next", 0, 16),
        BitField("flags_rsv", 0, 13),
        BitField("flags_indirect", 0, 1),
        BitField("flags_write", 0, 1),
        BitField("flags_next", 0, 1),
        BitField("len", 0, 32),
        BitField("addr", 0, 64),
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
        if type(data) == BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))


class VirtioVq(Packet):
    name = 'virtio_vq'
    fields_desc = [BitField("typ", 0, 2), BitField("qid", 0, 8)]
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
        if type(data) == BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))


class ErrInfo(Packet):
    name = 'err_info'
    fields_desc = [BitField("fatal", 0, 1), BitField("err_code", 0, 7)]
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
        if type(data) == BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))


class DescRspSbd(Packet):
    name = 'desc_rsp_sbd'
    fields_desc = [
        BitField("vq", 0, 10),
        BitField("dev_id", 0, 10),
        BitField("pkt_id", 0, 10),
        BitField("total_buf_length", 0, 18),
        BitField("valid_desc_cnt", 0, 16),
        BitField("ring_id", 0, 16),
        BitField("avail_idx", 0, 16),
        BitField("forced_shutdown", 0, 1),
        BitField("err_info", 0, 8),
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
        if type(data) == BinaryValue:
            return cls(data.buff)
        elif type(data) == int:
            return cls(data.to_bytes(len(cls()), "big"))
        else:
            raise ValueError("The {} type is not supported".format(type(data)))


# class VirtQDescFlags(Packet):
#     name = 'virtq_desc_flags'
#     fields_desc = [
#         BitField("rsv", 0, 13),
#         BitField("indirect", 0, 1),
#         BitField("write", 0, 1),
#         BitField("next", 0, 1),
#     ]
#     width = 0
#     for elemnt in fields_desc:
#         width += elemnt.size
#     padding_size = (8 - width) % 8
#     if padding_size:
#         fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
#     width += padding_size

#     def pack(self):
#         return int.from_bytes(self.build(), byteorder="big")

#     @classmethod
#     def unpack(cls, data):
#         if type(data) == BinaryValue:
#             return cls(data.buff)
#         elif type(data) == int:
#             return cls(data.to_bytes(len(cls()), "big"))
#         else:
#             raise ValueError("The {} type is not supported".format(type(data)))


# class VirtQDesc(Packet):
#     name = 'virtq_desc_flags'
#     fields_desc = [
#         BitField("next", 0, 13),
#         BitField("flags", 0, 16),
#         BitField("len", 0, 1),
#         BitField("addr", 0, 1),
#     ]
#     width = 0
#     for elemnt in fields_desc:
#         width += elemnt.size
#     padding_size = (8 - width) % 8
#     if padding_size:
#         fields_desc = [BitField("_rsv", 0, padding_size)] + fields_desc
#     width += padding_size

#     def pack(self):
#         return int.from_bytes(self.build(), byteorder="big")

#     @classmethod
#     def unpack(cls, data):
#         if type(data) == BinaryValue:
#             return cls(data.buff)
#         elif type(data) == int:
#             return cls(data.to_bytes(len(cls()), "big"))
#         else:
#             raise ValueError("The {} type is not supported".format(type(data)))


class TestType:
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2


class RefResult(NamedTuple):
    pkt_id: int
    ring_id: int
    avail_idx: int
    pkt_len: int
    descs: List
    err: ErrInfo
    seq_num: int
    idxs: List
    indirct_desc_buf: MemoryRegion


def typ_map(typ):
    _typ_map = {TestType.NETTX: "nettx", TestType.NETRX: "netrx", TestType.BLK: "blk"}
    return _typ_map[typ]


def qid2vq(qid, typ):
    return VirtioVq(qid=qid, typ=typ).pack()


def vq2qid(vq):
    vq = VirtioVq().unpack(vq)
    return vq.qid, vq.typ


def vq_str(vq):
    vq = VirtioVq().unpack(vq)
    return f"(qid:{vq.qid},typ:{typ_map(vq.typ)})"


def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)


def randbit(y):
    assert y >= 0
    return random.randint(0, 2**y - 1)


SchReqBus, SchReqTrans, SchReqMaster, SchReqSlaver, SchReqMonitor = define_stream(
    "sch_req", signals=["vq"], optional_signals=None, vld_signal="vld", rdy_signal="rdy"
)
NotifyRspBus, NotifyRspTrans, NotifyRspMaster, NotifyRspSlaver, NotifyRspMoniter = define_stream(
    "notify_rsp",
    signals=[
        "vq",
        "done",
        "cold",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
AllocSlotRspBus, AllocSlotRspTrans, AllocSlotRspMaster, AllocSlotRspSlaver, AllocSlotRspMoniter = define_stream(
    "alloc_slot_rsp",
    signals=[
        "dat_vq",
        "dat_pkt_id",
        "dat_ok",
        "dat_local_ring_empty",
        "dat_avail_ring_empty",
        "dat_q_stat_doing",
        "dat_q_stat_stopping",
        "dat_desc_engine_limit",
        "dat_err_info",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

AvailIdReqBus, AvailIdReqTrans, AvailIdReqMaster, AvailIdReqSlaver, AvailIdReqMoniter = define_stream(
    "avail_id_req",
    signals=[
        "vq",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
AvailIdRspBus, AvailIdRspTrans, AvailIdRspMaster, AvailIdRspSlaver, AvailIdRspMoniter = define_stream(
    "avail_id_rsp",
    signals=[
        "dat_id",
        "dat_idx",
        "dat_vq",
        "dat_local_ring_empty",
        "dat_avail_ring_empty",
        "dat_q_stat_doing",
        "dat_q_stat_stopping",
        "dat_err_info",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)

ResummerReqBus, ResummerRspBus, ResummerWrBus, ResummerReqTrans, ResummerRspTrans, ResummerWrTrans, ResummerMaster, ResummerSlaver = define_ram_tbl(
    "blk_desc_resummer",
    rd_req_signals=[
        "qid",
    ],
    rd_rsp_signals=[
        "dat",
    ],
    wr_signals=[
        "qid",
        "dat",
    ],
    rd_req_vld_signal="vld",
    rd_req_rdy_signal=None,
    rd_rsp_vld_signal="vld",
    wr_vld_signal="vld",
    wr_rdy_signal=None,
)
GlbInfoReqBus, GlbInfoRspBus, GlbInfoWrBus, GlbInfoReqTrans, GlbInfoRspTrans, GlbInfoWrTrans, GlbInfoMaster, GlbInfoSlaver = define_ram_tbl(
    "blk_desc_global_info",
    rd_req_signals=[
        "qid",
    ],
    rd_rsp_signals=[
        "bdf",
        "forced_shutdown",
        "desc_tbl_addr",
        "qdepth",
        "indirct_support",
        "segment_size_blk",
    ],
    wr_signals=None,
    rd_req_vld_signal="vld",
    rd_req_rdy_signal=None,
    rd_rsp_vld_signal="vld",
    wr_vld_signal=None,
    wr_rdy_signal=None,
)

LocInfoReqBus, LocInfoRspBus, LocInfoWrBus, LocInfoReqTrans, LocInfoRspTrans, LocInfoWrTrans, LocInfoMaster, LocInfoSlaver = define_ram_tbl(
    "blk_desc_local_info",
    rd_req_signals=[
        "qid",
    ],
    rd_rsp_signals=[
        "desc_tbl_addr_blk",
        "desc_tbl_size_blk",
        "desc_tbl_next_blk",
        "desc_tbl_id_blk",
        "desc_cnt",
        "data_len",
        "is_indirct",
    ],
    wr_signals=[
        "qid",
        "desc_tbl_addr_blk",
        "desc_tbl_size_blk",
        "desc_tbl_next_blk",
        "desc_tbl_id_blk",
        "desc_cnt",
        "data_len",
        "is_indirct",
    ],
    rd_req_vld_signal="vld",
    rd_req_rdy_signal=None,
    rd_rsp_vld_signal="vld",
    wr_vld_signal="vld",
    wr_rdy_signal=None,
)

BLKDescBus, BLKDescTrans, BLKDescMaster, BLKDescSlaver, BLKDescMoniter = define_stream(
    "blk_desc",
    signals=[
        "sop",
        "eop",
        "sbd",
        "dat",
    ],
    optional_signals=None,
    vld_signal="vld",
    rdy_signal="rdy",
)
