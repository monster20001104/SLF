from enum import IntEnum
from scapy.all import Packet, BitField
from test_func import BasePacket

class TestType(IntEnum):
    NETRX = 0x1
    NETTX = 0x0
    BLK = 0x2

class Nettx_Alloc_Slot_Rsp_Data(BasePacket):
    name = 'nettx_alloc_slot_rsp_dat'
    fields_desc = [
        BitField("vq", 0, 10),  # virtio_vq_t: typ(2) + qid(8)
        BitField("pkt_id", 0, 10),
        BitField("ok", 0, 1),
        BitField("local_ring_empty", 0, 1),
        BitField("avail_ring_empty", 0, 1),
        BitField("q_stat_doing", 0, 1),
        BitField("q_stat_stopping", 0, 1),
        BitField("desc_engine_limit", 0, 1),
        BitField("err_info", 0, 8), # virtio_err_info_t: fatal(1) + err_code(7)
    ]

class VirtioVq(BasePacket):
    name = 'virtio_vq'
    fields_desc = [
        BitField("typ", 0, 2),
        BitField("qid", 0, 8),
    ]

class VirioRspData(BasePacket):
    name = 'desc_rsp_data'
    fields_desc = [
        BitField("next", 0, 16),
        BitField("flag_rsv", 0, 13),
        BitField("flag_indirect", 0, 1),
        BitField("flag_write", 0, 1),
        BitField("flag_next", 0, 1),
        BitField("len", 0, 32),
        BitField("addr", 0, 64),
    ]

class VirioRspSbd(BasePacket):
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

class UsedInfoData(BasePacket):
    name = "used_info_data"
    fields_desc = [
        BitField("vq", 0, 10),
        BitField("len", 0, 32),
        BitField("id", 0, 32),
        BitField("used_idx", 0, 16),
        BitField("force_down", 0, 1), # forced_shutdown
        BitField("fatal", 0, 1),      # err_info.fatal
        BitField("err_info", 0, 7),   # err_info.err_code
    ]

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
    VIRTIO_ERR_CODE_DESC_ENG_RX_WRITE_MUST_BE_ONE = 0x17  # 7'h17
    VIRTIO_ERR_CODE_DESC_ENG_DESC_ZERO_LEN = 0x18  # 7'h18
    VIRTIO_ERR_CODE_DESC_ENG_PCIE_ERR = 0x19  # 7'h19
    VIRTIO_ERR_CODE_DESC_ENG_INDIRCT_NEXT_OVERSIZE = 0x1A  # 7'h1a（next over buf len）
    VIRTIO_ERR_CODE_DESC_ENG_DESC_BUF_LEN_OVERSIZE = 0x1B  # 7'h1b
    VIRTIO_ERR_CODE_NETRX_RCV_LEN_ERR = 0x20  # 7'h20
    VIRTIO_ERR_CODE_NETTX_PCIE_ERR = 0x30  # 7'h30


idx_avail_errcode_list = [
    VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_PCIE_ERR,
    VirtioErrCode.VIRTIO_ERR_CODE_IDX_ENG_INVALID_IDX,
    VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ENG_PCIE_ERR,
    VirtioErrCode.VIRTIO_ERR_CODE_AVAIL_ID_OVERSIZE,
]
