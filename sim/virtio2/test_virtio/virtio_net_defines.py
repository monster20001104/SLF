import sys
import logging
from dataclasses import dataclass
from typing import List, NamedTuple, Union, Tuple, Optional
from scapy.all import Packet, BitField
from enum import IntEnum
from cocotb.binary import BinaryValue


sys.path.append('../../common')
from generate_eth_pkg import Eth_Pkg_Cfg
from address_space import Pool, MemoryRegion

# from virtio_net_rx import *
# from virtio_net_tx import *


class VirtioCtrlRegOffset(IntEnum):
    BDF = 0x0
    DEV_ID = 0x8
    AVAIL_RING_ADDR = 0x10
    USED_RING_ADDR = 0x18
    DESC_ADDR = 0x20
    QSIZE = 0x28
    INDIRECT_SUPPORT = 0x30
    MAX_LEN = 0x38
    GENERATION = 0x40
    CTRL = 0x48
    AVAIL_IDX = 0x50
    BLK_DS_PTR = 0x50
    BLK_UP_PTR = 0x50
    AVAIL_UI_PTR = 0x58
    AVAIL_PI_PTR = 0x58
    AVAIL_CI_PTR = 0x58
    USED_PTR = 0x58
    SOC_NOTIFY = 0x60
    IDX_ENGINE_RD_REQ_NUM = 0x68
    IDX_ENGINE_RD_RSP_NUM = 0x68
    USED_ERR_FATAL_FLAG = 0x70
    USED_ELEM_PTR = 0x70
    ERR_INFO = 0x78
    MSIX_ADDR = 0x80
    MSIX_DATA = 0x88
    MSIX_ENABLE = 0x90
    MSIX_MASK = 0x98
    MSIX_PENDING = 0xA0
    MSIX_AGGREGATION_TIME = 0xA8
    MSIX_AGGREGATION_THRESHOLD = 0xB0
    IRQ_MERGE_INFO_UNIT0 = 0xB8
    IRQ_MERGE_INFO_UNIT1 = 0xB8
    IRQ_MERGE_INFO_UNIT2 = 0xB8
    IRQ_MERGE_INFO_UNIT3 = 0xB8
    IRQ_MERGE_INFO_UNIT4 = 0xC0
    IRQ_MERGE_INFO_UNIT5 = 0xC0
    IRQ_MERGE_INFO_UNIT6 = 0xC0
    IRQ_MERGE_INFO_UNIT7 = 0xC0
    QOS_ENABLE = 0x100
    QOS_L1_UNIT = 0x108
    QOS_L2_UNIT = 0x110
    NET_IDX_LIMIT = 0x130
    BLK_DESC_ENG_DESC_TBL_ADDR = 0x150
    BLK_DESC_ENG_DESC_TBL_SIZE = 0x158
    BLK_DESC_ENG_DESC_TBL_NEXT = 0x160
    BLK_DESC_ENG_DESC_TBL_ID = 0x160
    BLK_DESC_ENG_DESC_CNT = 0x160
    BLK_DESC_ENG_DATA_LEN = 0x168
    BLK_DESC_ENG_IS_INDIRCT = 0x168
    BLK_DESC_ENG_RESUMER = 0x168
    NET_DESC_ENGINE_HEAD_SLOT = 0x180
    NET_DESC_ENGINE_HEAD_SLOT_VLD = 0x180
    NET_DESC_ENGINE_TAIL_SLOT = 0x180
    NET_RX_IDX_LIMIT = 0x0
    NET_TX_IDX_LIMIT = 0x8


class GlobalRegOffset(IntEnum):
    RX_BUF_G_CSUM_EN_OFFSET = 0x660000
    RX_BUF_G_TIME_SEL_OFFSET = 0x660010
    RX_BUF_G_RANDOM_SEL_OFFSET = 0x660018
    BLK_DESC_ENGINE_MAX_CHAIN_LEN = 0x6c0000


class VirtioNetHdrFlagBit(IntEnum):
    VIRTIO_NET_HDR_F_NEEDS_CSUM = 0x1
    VIRTIO_NET_HDR_F_DATA_VALID = 0x2
    VIRTIO_NET_HDR_F_RSC_INFO = 0x4


class VirtioStatus(IntEnum):
    IDLE = 0x1
    STARTING = 0x2
    DOING = 0x4
    STOPPING = 0x8
    FORCED_SHUTDOWN = 0x10


class TestType(IntEnum):
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2


class VirtioNetHdrGsoTypeBit(IntEnum):
    VIRTIO_NET_HDR_GSO_NONE = 0
    VIRTIO_NET_HDR_GSO_TCPV4 = 1
    VIRTIO_NET_HDR_GSO_UDP = 3
    VIRTIO_NET_HDR_GSO_TCPV6 = 4
    VIRTIO_NET_HDR_GSO_ECN = 0x80


class VirtioErrCode(IntEnum):
    VIRTIO_ERR_CODE_NONE = 0x00  # 7'h00
    VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR = 0x71  # 7'h71
    VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX = 0x72  # 7'h72
    VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE = 0x03  # 7'h03
    VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR = 0x04  # 7'h04
    VIRTIO_ERR_CODE_DESC_ENG_DESC_NEXT_OVERSIZE = 0x10  # 7'h10
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE = 0x11  # 7'h11
    VIRTIO_ERR_CODE_DESC_ENG_DESC_CHAIN_DATA_LEN_OVERSIZE = 0x12  # 7'h12
    VIRTIO_ERR_CODE_DESC_ENG_UNSUPPORT_INDIRCT = 0x13  # 7'h13
    VIRTIO_ERR_CODE_DESC_ENG_NEXT_MUST_BE_ZERO = 0x14  # 7'h14
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NESTED_DESC = 0x15  # 7'h15
    VIRTIO_ERR_CODE_DESC_ENG_TX_WRITE_MUST_BE_ZERO = 0x16  # 7'h16
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE = 0x17  # 7'h17
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN = 0x18  # 7'h18
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR = 0x19  # 7'h19
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE = 0x1A  # 7'h1a（next over buf len）
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE = 0x1B  # 7'h1b
    # VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_WRITE_MUST_BE_ZERO = 0x1C  # 7'h1c
    VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR = 0x20  # 7'h20
    VIRTIO_ERR_CODE_NETTX_PCIE_ERR = 0x30  # 7'h30
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_NEXT_OVERSIZE = 0x40  # 7'h40
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_OVERSIZE = 0x41  # 7'h41
    VIRTIO_ERR_CODE_BLK_DESC_ENG_UNSUPPORT_INDIRCT = 0x43  # 7'h43
    VIRTIO_ERR_CODE_BLK_DESC_ENG_NEXT_MUST_BE_ZERO = 0x44  # 7'h44
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_NESTED_DESC = 0x45  # 7'h45
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_DATA_LEN_ZERO = 0x46  # 7'h46
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_CHAIN_LEN_ONE = 0x47  # 7'h47
    VIRTIO_ERR_CODE_BLK_DESC_ENG_PCIE_ERR = 0x48  # 7'h48
    VIRTIO_ERR_CODE_BLK_DESC_ENG_INDIRCT_DESC_NEXT_OVERSIZE = 0x49  # 7'h49
    VIRTIO_ERR_CODE_BLK_DESC_ENG_DESC_BUF_LEN_OVERSIZE = 0x4A  # 7'h4a
    VIRTIO_ERR_CODE_BLK_DOWN_PCIE_ERR = 0x50  # 7'h50


class VirtioBlkType(IntEnum):
    VIRTIO_BLK_T_IN = 0
    VIRTIO_BLK_T_OUT = 1  # write
    VIRTIO_BLK_T_FLUSH = 4
    VIRTIO_BLK_T_DISCARD = 11
    VIRTIO_BLK_T_WRITE_ZEROES = 13


class VirtBlkInfo:
    def __init__(self, id, fe_typ, fe_data=None, fe_len=None):
        self.id = id
        self.fe_typ = fe_typ
        self.fe_data = fe_data
        self.fe_len = fe_len
        self.fe_sts = None
        self.be_data = None
        self.be_sts = None
        self.be_err = None
        self.be_vq_gid = None
        self.be_host_gen = None
        self.be_forced_shutdown = None


@dataclass
class VirtBlkInfo:
    id: int
    fe_typ: int

    fe_data: Optional[bytes] = None
    fe_len: Optional[int] = None
    fe_sts: Optional[int] = None

    be_data: Optional[bytes] = None
    be_sts: Optional[int] = None
    
    be_err: Optional[int] = None
    be_vq_gid: Optional[int] = None
    be_host_gen: Optional[int] = None
    be_forced_shutdown: Optional[bool] = None


class VirtqBlkReqHeader(Packet):
    name = 'virtq_blk_req_hdr'
    fields_desc = [
        BitField("reserved1", 0, 32 * 10),
        BitField("magic_num", 0, 16),
        BitField("reserved", 0, 8),
        BitField("ctrl", 0, 8),
        BitField("host_buf_len", 0, 32),
        BitField("host_buf_addr", 0, 64),
        BitField("flags", 0, 16),
        BitField("desc_idx", 0, 16),
        BitField("err_info", 0, 8),
        BitField("vq_gen", 0, 8),
        BitField("vq_gid", 0, 16),
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
        if isinstance(data, BinaryValue):
            return cls(data.buff)
        if isinstance(data, int):
            return cls(data.to_bytes(len(cls()), "big"))
        if isinstance(data, bytes):
            return cls(data)
        raise ValueError(f"The {type(data)} type is not supported")


class VirtqBlkRspHeader(Packet):
    name = 'virtq_blk_rsp_hdr'
    fields_desc = [
        BitField("reserved1", 0, 32 * 10),
        BitField("magic_num", 0, 16),
        BitField("used_idx", 0, 16),
        BitField("used_len", 0, 32),
        BitField("host_buf_addr", 0, 64),
        BitField("flags", 0, 16),
        BitField("desc_idx", 0, 16),
        BitField("reserved", 0, 8),
        BitField("vq_gen", 0, 8),
        BitField("vq_gid", 0, 16),
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
        if isinstance(data, BinaryValue):
            return cls(data.buff)
        if isinstance(data, int):
            return cls(data.to_bytes(len(cls()), "big"))
        if isinstance(data, bytes):
            return cls(data)
        raise ValueError(f"The {type(data)} type is not supported")


class VirtioBlkOuthdr(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("sector", 0, 64),
        BitField("ioprio", 0, 32),
        BitField("type", 0, 32),
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
        if isinstance(data, BinaryValue):
            return cls(data.buff)
        if isinstance(data, int):
            return cls(data.to_bytes(len(cls()), "big"))
        if isinstance(data, bytes):
            return cls(data)
        raise ValueError(f"The {type(data)} type is not supported")


class VirtioNetHdr(Packet):
    name = 'virtq_desc'
    fields_desc = [
        BitField("num_buffers", 0, 16),
        BitField("csum_offset", 0, 16),
        BitField("csum_start", 0, 16),
        BitField("gso_size", 0, 16),
        BitField("hdr_len", 0, 16),
        BitField("gso_type", 0, 8),
        BitField("flags", 0, 8),
    ]

    width = 0
    for elemnt in fields_desc:
        width += elemnt.size

    def pack(self):
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data):
        return cls(data)


class VirtioVq(Packet):
    name = 'virtio_vq'

    _fields_desc_base = [
        BitField("typ", 0, 2),
        BitField("qid", 0, 8),
    ]

    _total_width = sum(field.size for field in _fields_desc_base)
    _padding_size = (8 - _total_width % 8) % 8
    fields_desc = [BitField("_rsv", 0, _padding_size)] + _fields_desc_base if _padding_size else _fields_desc_base
    width = _total_width + _padding_size

    _TYP_MAP = {member: member.name for member in TestType}

    @classmethod
    def qid2vq(cls, qid: int, typ: TestType) -> int:
        vq_instance = cls(qid=qid, typ=typ)
        return vq_instance.pack()

    @classmethod
    def vq2qid(cls, vq: Union[int, BinaryValue, "VirtioVq"]) -> Tuple[int, TestType]:
        if isinstance(vq, cls):
            vq_instance = vq
        else:
            vq_instance = cls.unpack(vq)
        return vq_instance.qid, vq_instance.typ

    @classmethod
    def vq2str(cls, vq: Union[int, BinaryValue, "VirtioVq"]) -> str:
        qid, typ = cls.vq2qid(vq)
        typ_str = cls._TYP_MAP.get(typ, f"UNKNOWN({typ})")
        return f"(qid:{qid}, typ:{typ_str})"

    def pack(self) -> int:
        return int.from_bytes(self.build(), byteorder="big")

    @classmethod
    def unpack(cls, data: Union[int, BinaryValue]) -> "VirtioVq":
        if isinstance(data, BinaryValue):
            return cls(data.buff)
        elif isinstance(data, int):
            byte_len = (cls.width + 7) // 8
            return cls(data.to_bytes(byte_len, byteorder="big"))
        else:
            raise ValueError(f"不支持的数据类型：{type(data)}，仅支持 int/BinaryValue")


class VirtqUsedElement(Packet):
    name = 'virtq_used_elem'
    fields_desc = [BitField("len", 0, 32), BitField("id", 0, 32)]
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
        elif type(data) == bytes:
            return cls(data)
        else:
            raise ValueError("The {} type is not supported".format(type(data)))


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


class Mbufs(NamedTuple):
    regs: List[MemoryRegion]
    len: int
    typ: Optional[VirtioBlkType] = None


class IO_Req_Type(NamedTuple):
    data: bytearray
    host_gen: int
    start_of_pkt: bool
    end_of_pkt: bool
    forced_shutdown: bool
    err_info: int


class Net2TsoPkt(NamedTuple):
    qid: int
    length: int
    gen: int
    err: bool
    tso_en: bool
    csum_en: bool
    data: bytes


class Cfg(NamedTuple):
    rx_en: bool
    tx_en: bool
    blk_en: bool
    q_num: int
    max_seq: int
    dma_latency: int
    max_len: int
    max_len_rx: int
    min_chain_num: int
    max_chain_num: int
    max_indirct_ptr: int
    max_indirct_desc_size: int
    qsz_width_list: List
    eth_cfg: Eth_Pkg_Cfg
    qos_en: bool
    random_qos: float
    msix_en: int
    random_msix_en: float
    random_msix_mask: float
    indirct_support: bool
    indirct_relaxed_ordering: bool

    rx_random_need_vld: float
    global_rx_csum_en: bool
    global_rx_time_sel: int
    global_rx_random_sel: int
    global_rx_beq_pps: float
    global_rx_beq_bps: float

    global_tx_tso_en: bool
    global_tx_csum_en: bool
    tx_random_need_tso: float

    fault_injection: bool
    restart_en: bool


smoke_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=8,
    max_seq=100,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=8,
    max_indirct_ptr=8,
    max_indirct_desc_size=(64 * 1024 // 16),
    # qsz_width_list          = [6, 8],
    qsz_width_list=[5],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0.5,
    qos_en=False,
    random_qos=0.5,  # the random of qos == 1
    msix_en=0,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=True,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=1,
    global_rx_random_sel=1,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=50_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=True,
    restart_en=True,
)


Test_1Q_pps_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=1,
    max_seq=5000,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=1,
    max_indirct_ptr=1,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[10],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=False,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=False,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=10,  # M float
    global_rx_beq_bps=25_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_1Q_pps_cfg.eth_cfg.test_mode = "pps"


Test_nQ_pps_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=8,
    max_seq=1000,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=1,
    max_indirct_ptr=1,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[10],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=False,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=False,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=50_000,
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_nQ_pps_cfg.eth_cfg.test_mode = "pps"

Test_1Q_bps_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=1,
    max_seq=100,
    dma_latency=8000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=16,
    max_indirct_ptr=16,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[10],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=False,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=True,
    indirct_relaxed_ordering=False,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=10,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_1Q_bps_cfg.eth_cfg.test_mode = "bps"


Test_nQ_bps_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=8,
    max_seq=200,
    dma_latency=5000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=1,
    max_indirct_ptr=1,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[10],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=False,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=False,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=15_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_nQ_bps_cfg.eth_cfg.test_mode = "bps"
Test_nQ_bps_cfg.eth_cfg.random_vlan = 0

Test_1Q_longchain_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=1,
    max_seq=200,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=64,
    max_chain_num=128,
    max_indirct_ptr=1,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[8, 8, 9, 9, 10, 10, 15],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=True,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=False,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_1Q_longchain_cfg.eth_cfg.test_mode = "bps"
Test_1Q_longchain_cfg.eth_cfg.random_vlan = 0

Test_nQ_longchain_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=8,
    max_seq=50,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=128,
    max_indirct_ptr=1,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[8, 8, 9, 9, 10, 10, 15],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=True,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=False,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_1Q_longchain_indirct_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=1,
    max_seq=200,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=128,
    max_indirct_ptr=128,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[8, 8, 9, 9, 10, 10, 15],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=True,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=True,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_nQ_longchain_indirct_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=8,
    max_seq=200,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=128,
    max_indirct_ptr=128,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[8, 8, 9, 9, 10, 10, 15],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=True,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=True,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_1Q_indirct_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=1,
    max_seq=200,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=8,
    max_indirct_ptr=8,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[8, 8, 9, 9, 10, 10, 15],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=True,
    random_qos=0.5,  # the random of qos == 1
    msix_en=1,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=True,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)
Test_nQ_indirct_cfg = Cfg(
    rx_en=True,
    tx_en=True,
    blk_en=True,
    q_num=8,
    max_seq=20,
    dma_latency=2000,
    max_len=65562,  # 64KB max TCP payload + 12B virtio-net header + 14B eth header
    max_len_rx=2048,
    min_chain_num=1,
    max_chain_num=8,
    max_indirct_ptr=8,
    max_indirct_desc_size=(64 * 1024 // 16),
    qsz_width_list=[8, 8, 9, 9, 10, 10, 15],
    eth_cfg=Eth_Pkg_Cfg(),
    rx_random_need_vld=0,
    qos_en=True,
    random_qos=0.5,  # the random of qos == 1
    msix_en=0,  # the init of msix_en
    random_msix_en=0,  # the random of msix_en change
    random_msix_mask=0,  # the random of msix_en change
    indirct_support=True,
    indirct_relaxed_ordering=True,
    global_rx_csum_en=False,
    global_rx_time_sel=0,
    global_rx_random_sel=0,
    global_rx_beq_pps=20,  # M float
    global_rx_beq_bps=10_000,  # M float
    global_tx_tso_en=False,
    global_tx_csum_en=False,
    tx_random_need_tso=0.5,
    fault_injection=False,
    restart_en=False,
)


if __name__ == "__main__":
    a = VirtioVq(qid=1, typ=TestType.BLK)
    print(VirtioVq.vq2str(a))
