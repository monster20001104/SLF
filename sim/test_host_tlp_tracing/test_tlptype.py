###########################################
# 文件名称 : test_tlptype
# 作者名称 : 崔飞翔
# 创建日期 : 2025/08/29
# 功能描述 : 
# 
# 修改记录 : 
# 
# 修改日期 : 2025/08/29
# 版本号    修改人    修改内容
# v1.0     崔飞翔     初始化版本
###########################################
from typing import List,NamedTuple
from enum import Enum, IntEnum
from cocotb.triggers import Event
from bus.tlp_adap_bypass_bus import  OpCode


class ComplStatus(Enum):
    SC  = 0
    UR  = 1
    CRS = 2
    CA  = 4

class TlpBypass():
    def get_first_be_offset(self):
        if self.first_be & 0x7 == 0:
            return 3
        elif self.first_be & 0x3 == 0:
            return 2
        elif self.first_be & 0x1 == 0:
            return 1
        else:
            return 0
    def get_last_be_offset(self):
        if self.byte_length == 4:
            be = self.first_be
        else:
            be = self.last_be
        if be & 0xf == 0x1:
            return 3
        elif be & 0xe == 0x2:
            return 2
        elif be & 0xc == 0x4:
            return 1
        else:
            return 0
    def get_be_byte_count(self):
        return self.byte_length - self.get_first_be_offset() - self.get_last_be_offset()

class TlpBypassReqBase(NamedTuple):
    op_code: OpCode
    addr: int
    cpl_byte_count: int
    byte_length: int
    tag: int
    cpl_id: int #req.req_id
    req_id: int #upstream bdf
    cpl_status: ComplStatus
    first_be: int
    last_be: int
    dest_id: int
    ext_reg_num: int
    reg_num: int
    data: bytes
    event: Event

class TlpBypassReq(TlpBypassReqBase, TlpBypass):
    pass

class TlpFmt(IntEnum):
    THREE_DW       = 0x0
    FOUR_DW        = 0x1
    THREE_DW_DATA  = 0x2
    FOUR_DW_DATA   = 0x3
    TLP_PREFIX     = 0x4

class TlpType(Enum):
    MEM_READ           = (TlpFmt.THREE_DW,      0x00)
    MEM_READ_64        = (TlpFmt.FOUR_DW,       0x00)
    MEM_WRITE          = (TlpFmt.THREE_DW_DATA, 0x00)
    MEM_WRITE_64       = (TlpFmt.FOUR_DW_DATA,  0x00)
    CFG_READ_0         = (TlpFmt.THREE_DW,      0x04)
    CFG_WRITE_0        = (TlpFmt.THREE_DW_DATA, 0x04)
    CFG_READ_1         = (TlpFmt.THREE_DW,      0x05)
    CFG_WRITE_1        = (TlpFmt.THREE_DW_DATA, 0x05)
    CPL                = (TlpFmt.THREE_DW,      0x0A)
    CPL_DATA           = (TlpFmt.THREE_DW_DATA, 0x0A)
 
    
    @property
    def fmt(self):
        return self.value[0]
    
    @property
    def type_code(self):
        return self.value[1]
    
    @classmethod
    def from_fmt_type(cls, fmt: int, type_code: int):
        for tlp_type in cls:
            if tlp_type.fmt == fmt and tlp_type.type_code == type_code:
                return tlp_type
        return None
    
USED_TLP_TYPES = {
    TlpType.MEM_READ,
    TlpType.MEM_READ_64,
    TlpType.MEM_WRITE,
    TlpType.MEM_WRITE_64,
    TlpType.CFG_READ_0,
    TlpType.CFG_WRITE_0,
    TlpType.CFG_READ_1,
    TlpType.CFG_WRITE_1,
    TlpType.CPL,
    TlpType.CPL_DATA
}    

class FmtType_t:
    def __init__(self, fmt: TlpFmt = None, type_code: int = 0):
        self.fmt = fmt if fmt is not None else TlpFmt.THREE_DW
        self.type_code = type_code
    
    @classmethod
    def from_int(cls, value: int):
        fmt_val = (value >> 29) & 0x7  # 位[31:29]
        type_code = (value >> 24) & 0x1F  # 位[28:24]
        try:
            fmt = TlpFmt(fmt_val)
        except ValueError:
            fmt = TlpFmt.THREE_DW  # 默认值
        
        return cls(fmt, type_code)
    
    def to_int(self) -> int:
        return (self.fmt.value << 29) | (self.type_code << 24)
    
    def get_tlp_type(self) -> TlpType:
        return TlpType.from_fmt_type(self.fmt, self.type_code)
    
class TlpHeader_DW0_t:
    def __init__(self, fmt_type: FmtType_t = None, reserved_b23: int = 0, tc: int = 0,
                 reserved_b19: int = 0, attr_2: int = 0, lwn: int = 0, th: int = 0,
                 td: int = 0, ep: int = 0, attr_1_0: int = 0, at: int = 0, length_dw: int = 0):
        self.fmt_type = fmt_type if fmt_type is not None else FmtType_t()
        self.reserved_b23 = reserved_b23  # 1位
        self.tc = tc  # 3位
        self.reserved_b19 = reserved_b19  # 1位
        self.attr_2 = attr_2  # 1位
        self.lwn = lwn  # 1位
        self.th = th  # 1位
        self.td = td  # 1位
        self.ep = ep  # 1位
        self.attr_1_0 = attr_1_0  # 2位
        self.at = at  # 2位
        self.length_dw = length_dw  # 10位
    
    @classmethod
    def from_int(cls, value: int):
        fmt_type = FmtType_t.from_int(value)
        reserved_b23 = (value >> 23) & 0x1
        tc = (value >> 20) & 0x7
        reserved_b19 = (value >> 19) & 0x1
        attr_2 = (value >> 18) & 0x1
        lwn = (value >> 17) & 0x1
        th = (value >> 16) & 0x1
        td = (value >> 15) & 0x1
        ep = (value >> 14) & 0x1
        attr_1_0 = (value >> 12) & 0x3
        at = (value >> 10) & 0x3
        length_dw = value & 0x3FF
        
        return cls(fmt_type, reserved_b23, tc, reserved_b19, attr_2, lwn, th, td, ep, attr_1_0, at, length_dw)
    
    def to_int(self):
        value = self.fmt_type.to_int()
        value |= (self.reserved_b23 & 0x1) << 23
        value |= (self.tc & 0x7) << 20
        value |= (self.reserved_b19 & 0x1) << 19
        value |= (self.attr_2 & 0x1) << 18
        value |= (self.lwn & 0x1) << 17
        value |= (self.th & 0x1) << 16
        value |= (self.td & 0x1) << 15
        value |= (self.ep & 0x1) << 14
        value |= (self.attr_1_0 & 0x3) << 12
        value |= (self.at & 0x3) << 10
        value |= self.length_dw & 0x3FF
        
        return value

class TlpHeader_DW1_Req_t:
    def __init__(self, req_id: int = 0, tag: int = 0, last_be: int = 0, first_be: int = 0):
        self.req_id = req_id  # 16位
        self.tag = tag  # 8位
        self.last_be = last_be  # 4位
        self.first_be = first_be  # 4位
    
    @classmethod
    def from_int(cls, value: int):
        req_id = (value >> 16) & 0xFFFF
        tag = (value >> 8) & 0xFF
        last_be = (value >> 4) & 0xF
        first_be = value & 0xF
        
        return cls(req_id, tag, last_be, first_be)
    
    def to_int(self):
        value = (self.req_id & 0xFFFF) << 16
        value |= (self.tag & 0xFF) << 8
        value |= (self.last_be & 0xF) << 4
        value |= self.first_be & 0xF
        
        return value

class TlpHeader_DW1_CplD_t:
    def __init__(self, cpl_id: int = 0, cpl_status: int = 0, bcm: int = 0, byte_count: int = 0):
        self.cpl_id = cpl_id  # 16位
        self.cpl_status = cpl_status  # 3位
        self.bcm = bcm  # 1位
        self.byte_count = byte_count  # 12位
    
    @classmethod
    def from_int(cls, value: int):
        cpl_id = (value >> 16) & 0xFFFF
        cpl_status = (value >> 13) & 0x7
        bcm = (value >> 12) & 0x1
        byte_count = value & 0xFFF
        
        return cls(cpl_id, cpl_status, bcm, byte_count)
    
    def to_int(self):
        value = (self.cpl_id & 0xFFFF) << 16
        value |= (self.cpl_status & 0x7) << 13
        value |= (self.bcm & 0x1) << 12
        value |= self.byte_count & 0xFFF
        
        return value

class TlpHeader_DW2_Req32b_t:
    def __init__(self, addr_low_dw: int = 0, ph: int = 0):
        self.addr_low_dw = addr_low_dw  # 30位
        self.ph = ph  # 2位
    
    @classmethod
    def from_int(cls, value: int):
        addr_low_dw = (value >> 2) & 0x3FFFFFFF
        ph = value & 0x3
        
        return cls(addr_low_dw, ph)
    
    def to_int(self):
        value = (self.addr_low_dw & 0x3FFFFFFF) << 2
        value |= self.ph & 0x3
        
        return value

class TlpHeader_DW2_Req64b_t:
    def __init__(self, addr_high: int = 0):
        self.addr_high = addr_high  # 32位
    
    @classmethod
    def from_int(cls, value: int):
        return cls(value)
    
    def to_int(self):
        return self.addr_high

class TlpHeader_DW2_CplD_t:
    def __init__(self, req_id: int = 0, tag: int = 0, reserved_b7: int = 0, lower_addr: int = 0):
        self.req_id = req_id  # 16位
        self.tag = tag  # 8位
        self.reserved_b7 = reserved_b7  # 1位
        self.lower_addr = lower_addr  # 7位
    
    @classmethod
    def from_int(cls, value: int):
        req_id = (value >> 16) & 0xFFFF
        tag = (value >> 8) & 0xFF
        reserved_b7 = (value >> 7) & 0x1
        lower_addr = value & 0x7F
        
        return cls(req_id, tag, reserved_b7, lower_addr)
    
    def to_int(self):
        value = (self.req_id & 0xFFFF) << 16
        value |= (self.tag & 0xFF) << 8
        value |= (self.reserved_b7 & 0x1) << 7
        value |= self.lower_addr & 0x7F
        
        return value

class TlpHeader_DW2_CFG_t:
    def __init__(self, dest_id: int = 0, reserved_b4: int = 0, ext_reg_num: int = 0, 
                 reg_num: int = 0, reserved_b2: int = 0):
        self.dest_id = dest_id  # 16位
        self.reserved_b4 = reserved_b4  # 4位
        self.ext_reg_num = ext_reg_num  # 4位
        self.reg_num = reg_num  # 6位
        self.reserved_b2 = reserved_b2  # 2位
    
    @classmethod
    def from_int(cls, value: int):
        dest_id = (value >> 16) & 0xFFFF
        reserved_b4 = (value >> 12) & 0xF
        ext_reg_num = (value >> 8) & 0xF
        reg_num = (value >> 2) & 0x3F
        reserved_b2 = value & 0x3
        
        return cls(dest_id, reserved_b4, ext_reg_num, reg_num, reserved_b2)
    
    def to_int(self):
        value = (self.dest_id & 0xFFFF) << 16
        value |= (self.reserved_b4 & 0xF) << 12
        value |= (self.ext_reg_num & 0xF) << 8
        value |= (self.reg_num & 0x3F) << 2
        value |= self.reserved_b2 & 0x3
        
        return value

class TlpHeader_DW3_Req64b_t:
    def __init__(self, addr_low_dw: int = 0, ph: int = 0):
        self.addr_low_dw = addr_low_dw  # 30位
        self.ph = ph  # 2位
    
    @classmethod
    def from_int(cls, value: int):
        addr_low_dw = (value >> 2) & 0x3FFFFFFF
        ph = value & 0x3
        
        return cls(addr_low_dw, ph)
    
    def to_int(self):
        value = (self.addr_low_dw & 0x3FFFFFFF) << 2
        value |= self.ph & 0x3
        
        return value

class TlpHeader:
    def __init__(self):
        self.dw0 = TlpHeader_DW0_t()
        self.dw1 = None  
        self.dw2 = None  
        self.dw3 = None  
        self.tlp_type = None  
    
    @classmethod
    def from_dwords(cls, dw0: int, dw1: int, dw2: int, dw3: int):
        tlp = cls()
        tlp.dw0 = TlpHeader_DW0_t.from_int(dw0)
        
        tlp.tlp_type = tlp.dw0.fmt_type.get_tlp_type()
        
        if tlp.tlp_type not in USED_TLP_TYPES:
            return None
        
        if tlp.tlp_type in [TlpType.CPL, TlpType.CPL_DATA]:
            tlp.dw1 = TlpHeader_DW1_CplD_t.from_int(dw1)
        else:
            tlp.dw1 = TlpHeader_DW1_Req_t.from_int(dw1)
        
        if tlp.tlp_type in [TlpType.MEM_READ, TlpType.MEM_WRITE]:
            tlp.dw2 = TlpHeader_DW2_Req32b_t.from_int(dw2)
            tlp.dw3 = 0
        elif tlp.tlp_type in [TlpType.MEM_READ_64, TlpType.MEM_WRITE_64]:
            tlp.dw2 = TlpHeader_DW2_Req64b_t.from_int(dw2)
            tlp.dw3 = TlpHeader_DW3_Req64b_t.from_int(dw3)
        elif tlp.tlp_type in [TlpType.CPL, TlpType.CPL_DATA]:
            tlp.dw2 = TlpHeader_DW2_CplD_t.from_int(dw2)
            tlp.dw3 = 0
        elif tlp.tlp_type in [TlpType.CFG_READ_0, TlpType.CFG_WRITE_0,
                           TlpType.CFG_READ_1, TlpType.CFG_WRITE_1]:
            tlp.dw2 = TlpHeader_DW2_CFG_t.from_int(dw2)
            tlp.dw3 = 0
        
        return tlp
    
    def to_dwords(self) -> List[int]:
        dw0 = self.dw0.to_int()
        dw1 = self.dw1.to_int() if self.dw1 else 0
        dw2 = self.dw2.to_int() if self.dw2 else 0
        dw3 = self.dw3.to_int() if self.dw3 else 0
        
        return [dw0, dw1, dw2, dw3]
    
    def set_tlp_type(self, tlp_type: TlpType):
        self.tlp_type = tlp_type
        self.dw0.fmt_type.fmt = tlp_type.fmt
        self.dw0.fmt_type.type_code = tlp_type.type_code

class Data256_t:
    def __init__(self, data: int = 0):
        self.data = data
    
    def get_low_128b(self) -> int:
        return self.data & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    
    def get_high_128b(self) -> int:
        return (self.data >> 128) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    
    def set_low_128b(self, value: int):
        self.data = (self.data & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000) | (value & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    
    def set_high_128b(self, value: int):
        self.data = (self.data & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | ((value & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) << 128)
    
    @classmethod
    def from_two_128b(cls, low_128b: int, high_128b: int):
        return cls(low_128b | (high_128b << 128))

class AVST256QW_2ch_t:
    def __init__(self, data: Data256_t = None, sop: int = 0, eop: int = 0, valid: int = 0):
        self.data = data if data is not None else Data256_t()
        self.sop = sop  # 2位，位0表示通道0，位1表示通道1
        self.eop = eop  # 2位，位0表示通道0，位1表示通道1
        self.valid = valid  # 2位，位0表示通道0，位1表示通道1
    
    def get_channel_data(self, channel: int) -> int:
        if channel == 0:
            return self.data.get_low_128b()
        elif channel == 1:
            return self.data.get_high_128b()
        else:
            raise ValueError("channel must 0 or 1")
    
    def set_channel_data(self, channel: int, value: int):
        if channel == 0:
            self.data.set_low_128b(value)
        elif channel == 1:
            self.data.set_high_128b(value)
        else:
            raise ValueError("channel must 0 or 1")
    
    def get_channel_sop(self, channel: int) -> bool:
        if channel == 0:
            return bool(self.sop & 0x1)
        elif channel == 1:
            return bool(self.sop & 0x2)
        else:
            raise ValueError("channel must 0 or 1")
    
    def set_channel_sop(self, channel: int, value: bool):
        if channel == 0:
            self.sop = (self.sop & 0x2) | (int(value) & 0x1)
        elif channel == 1:
            self.sop = (self.sop & 0x1) | ((int(value) << 1) & 0x2)
        else:
            raise ValueError("channel must 0 or 1")
    
    def get_channel_eop(self, channel: int) -> bool:
        if channel == 0:
            return bool(self.eop & 0x1)
        elif channel == 1:
            return bool(self.eop & 0x2)
        else:
            raise ValueError("channel must 0 or 1")
    
    def set_channel_eop(self, channel: int, value: bool):
        if channel == 0:
            self.eop = (self.eop & 0x2) | (int(value) & 0x1)
        elif channel == 1:
            self.eop = (self.eop & 0x1) | ((int(value) << 1) & 0x2)
        else:
            raise ValueError("channel must 0 or 1")
    
    def get_channel_valid(self, channel: int) -> bool:
        if channel == 0:
            return bool(self.valid & 0x1)
        elif channel == 1:
            return bool(self.valid & 0x2)
        else:
            raise ValueError("channel must 0 or 1")
    
    def set_channel_valid(self, channel: int, value: bool):
        if channel == 0:
            self.valid = (self.valid & 0x2) | (int(value) & 0x1)
        elif channel == 1:
            self.valid = (self.valid & 0x1) | ((int(value) << 1) & 0x2)
        else:
            raise ValueError("channel must 0 or 1")


