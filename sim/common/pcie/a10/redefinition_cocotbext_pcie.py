
import cocotbext.pcie.core as _core
globals().update(_core.__dict__)
from cocotbext.pcie.core.utils import PcieId
from cocotbext.pcie.core.tlp import Tlp, TlpType, CplStatus
from cocotbext.pcie.core.rc import RootComplex as _OriginalRootComplex


import types
__all__ = [name for name, obj in globals().items()
           if not name.startswith('_') and
              not isinstance(obj, types.ModuleType)]

async def redefinition_config_read(self, dev, addr, length, timeout=0, timeout_unit='ns'):
    n = 0
    data = b''

    while True:
        tlp = Tlp()
        tlp.fmt_type = TlpType.CFG_READ_1
        tlp.requester_id = PcieId(0, 0, 0)
        tlp.dest_id = dev

        first_pad = addr % 4
        byte_length = min(length-n, 4-first_pad)
        tlp.set_addr_be(addr, byte_length)

        tlp.register_number = addr >> 2

        tlp.tag = await self.alloc_tag()

        await self.send(tlp)
        cpl = await self.recv_cpl(tlp.tag, timeout, timeout_unit)
        if cpl.lower_address != 0:
            raise ValueError("lower_address:{} lower_address != 0".format(cpl.lower_address))
        if cpl.status != CplStatus.UR and cpl.byte_count != 4:
            raise ValueError("byte_count:{} byte_count != 4".format(cpl.byte_count))
        self.release_tag(tlp.tag)

        if not cpl or cpl.status != CplStatus.SC:
            d = b'\xff\xff\xff\xff'
        else:
            assert cpl.length == 1
            d = cpl.get_data()

        data += d[first_pad:]

        n += byte_length
        addr += byte_length

        if n >= length:
            break

    return data[:length]

class RootComplex(_OriginalRootComplex):
    config_read = redefinition_config_read

globals()['RootComplex'] = RootComplex
if 'RootComplex' in __all__:
    __all__[__all__.index('RootComplex')] = 'RootComplex'