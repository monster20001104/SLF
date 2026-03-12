import sys
import os

# 获取目标目录的规范路径
target_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../rom_init')
sys.path.append(os.path.normpath(target_dir))  # 规范化路径

from rom_init import convert_mif
from reg_idx_tbl_lib import *


def main():

    RIT = Register_Index_Table()
    # Minor_Version    Major_Version
    RIT.header_set(0x00, 0x01)
    # Minor_Version    Major_Version    BAR_Index    Type    Register_Region_Byte_Offset    Register_Region_Length
    RIT.entry_add(0x00, 0x01, 0x00, 0x01, 0x000_0000, 0x10_0000)  # mgmt 
    RIT.entry_add(0x00, 0x01, 0x00, 0x02, 0x040_0000, 0x10_0000)  # pcie_switch
    RIT.entry_add(0x00, 0x01, 0x00, 0x03, 0x080_0000, 0x08_0000)  # beq
    RIT.entry_add(0x00, 0x01, 0x00, 0x04, 0x088_0000, 0x04_0000)  # net_beq_qid_mapping
    RIT.entry_add(0x00, 0x01, 0x00, 0x05, 0x08C_0000, 0x04_0000)  # blk_beq_qid_mapping
    RIT.entry_add(0x00, 0x01, 0x00, 0x06, 0x090_0000, 0x00_1000)  # net_beq_qid_mapping_control
    RIT.entry_add(0x00, 0x01, 0x00, 0x07, 0x090_1000, 0x00_1000)  # blk_beq_qid_mapping_control
    RIT.entry_add(0x00, 0x01, 0x00, 0x08, 0x100_0000, 0x40_0000)  # emu
    RIT.entry_add(0x00, 0x01, 0x00, 0x09, 0x180_0000, 0x40_0000)  # virtio
    RIT.entry_add(0x00, 0x01, 0x00, 0x0A, 0x200_0000, 0x40_0000)  # qos
    RIT.entry_add(0x00, 0x01, 0x00, 0x0B, 0x020_1000, 0x00_1000)  # host_tlp_adaptor  
    # suffix : "mif"
    wr_csv(suffix="mif", RIT=RIT)
    convert_mif("reg_idx_tbl_rom.mif", replace=True)
    # convert_mif("reg_idx_tbl_rom.mif", replace=False)
    # wr_csv(suffix="mif", RIT=RIT, SIM=True)


if __name__ == "__main__":
    main()
