class Register_Index_Table_Header:
    Minor_Version = 0
    Major_Version = 0
    Magic_Number = 0x4CFD
    Number_of_Table_Entries = 0

    def __init__(self):
        pass

    def header_set(
        self,
        Minor_Version,
        Major_Version,
    ):
        self.Minor_Version = Minor_Version
        self.Major_Version = Major_Version

    def get_dw(
        self,
        idx,
    ) -> int:
        if idx == 0:
            return self.Magic_Number + (self.Major_Version << 16) + (self.Minor_Version << 24)
        elif idx == 1:
            return self.Number_of_Table_Entries
        else:
            return 0


class Register_Index_Table_Entry:
    Minor_Version = 0
    Major_Version = 0
    BAR_Index = 0
    Type = 0
    Register_Region_Byte_Offset = 0
    Register_Region_Length = 0

    def __init__(
        self,
        Minor_Version,
        Major_Version,
        BAR_Index,
        Type,
        Register_Region_Byte_Offset,
        Register_Region_Length,
    ):
        self.Minor_Version = Minor_Version
        self.Major_Version = Major_Version
        self.BAR_Index = BAR_Index
        self.Type = Type
        self.Register_Region_Byte_Offset = Register_Region_Byte_Offset
        self.Register_Region_Length = Register_Region_Length

    def get_dw(
        self,
        idx,
    ) -> int:
        if idx == 0:
            return (
                self.Type
                + (self.BAR_Index << 8)
                + (self.Major_Version << 16)
                + (self.Minor_Version << 24)
            )
        elif idx == 1:
            return self.Register_Region_Byte_Offset
        elif idx == 2:
            return self.Register_Region_Length
        else:
            return 0


class Register_Index_Table:
    RITH = Register_Index_Table_Header()
    RITE = []

    def __init__(self):
        pass

    def header_set(
        self,
        Minor_Version,
        Major_Version,
    ):
        self.RITH.header_set(Minor_Version, Major_Version)

    def entry_add(
        self,
        Minor_Version,
        Major_Version,
        BAR_Index,
        Type,
        Register_Region_Byte_Offset,
        Register_Region_Length,
    ):
        self.RITH.Number_of_Table_Entries += 1
        self.RITE.append(
            Register_Index_Table_Entry(
                Minor_Version,
                Major_Version,
                BAR_Index,
                Type,
                Register_Region_Byte_Offset,
                Register_Region_Length,
            )
        )


def wr_csv(
    suffix="mif",
    RIT=Register_Index_Table(),
    SIM=False,
):
    global str_csv
    str_csv = ""
    if suffix == "coe":
        str_csv += f"memory_initialization_radix = 16;\n" f"memory_initialization_vector = \n"
        str_csv += f"{RIT.RITH.get_dw(0):016x},\n"
        str_csv += f"{RIT.RITH.get_dw(1):016x},\n"
        str_csv += f"{RIT.RITH.get_dw(2):016x},\n"
        str_csv += f"{RIT.RITH.get_dw(3):016x},\n"

        for RITE in RIT.RITE:
            str_csv += f"{RITE.get_dw(0):016x},\n"
            str_csv += f"{RITE.get_dw(1):016x},\n"
            str_csv += f"{RITE.get_dw(2):016x},\n"
            str_csv += f"{RITE.get_dw(3):016x},\n"

        str_csv = str_csv[0:-2]
        str_csv += ";"
        file = open("reg_idx_tbl_rom.coe", 'w')
        file.write(str_csv)
        file.close()
    elif suffix == "mif":
        # DEPTH = 16;//存储器的深度，就是存多少个数据
        # WIDTH = 8;//存储器的数据位宽，就是每个数据多少位
        # ADDRESS_RADIX = HEX;//设置地址基值的进制表示，可以设为BIN（二进制），OCT（八进制），DEC(十进制)，HEX(十六进制)
        # DATA_RADIX = HEX;//设置数据基值的进制表示， 同上
        # CONTENT BEGIN//数据区开始

        str_csv += (
            f"DEPTH = {RIT.RITH.Number_of_Table_Entries*4+4};\n"
            f"WIDTH = 64;\n"
            f"ADDRESS_RADIX = HEX;\n"
            f"DATA_RADIX = HEX;\n"
            f"CONTENT BEGIN\n"
        )

        dw_idx = 0
        str_csv += f"{dw_idx:04x}:{RIT.RITH.get_dw(0)+(RIT.RITH.get_dw(1)<<32):016x};\n"

        # dw_idx += 1
        # str_csv += f"{dw_idx:04x}:{RIT.RITH.get_dw(1):016x};\n"

        dw_idx += 1
        str_csv += f"{dw_idx:04x}:{RIT.RITH.get_dw(2)+(RIT.RITH.get_dw(3)<<32):016x};\n"

        # dw_idx += 1
        # str_csv += f"{dw_idx:04x}:{RIT.RITH.get_dw(3):016x};\n"

        for RITE in RIT.RITE:
            dw_idx += 1
            str_csv += f"{dw_idx:04x}:{RITE.get_dw(0)+(RITE.get_dw(1)<<32):016x};\n"

            # dw_idx += 1
            # str_csv += f"{dw_idx:04x}:{RITE.get_dw(1):016x};\n"

            dw_idx += 1
            str_csv += f"{dw_idx:04x}:{RITE.get_dw(2)+(RITE.get_dw(3)<<32):016x};\n"

            # dw_idx += 1
            # str_csv += f"{dw_idx:04x}:{RITE.get_dw(3):016x};\n"

        str_csv += f"END;"
        file = open("reg_idx_tbl_rom.mif", 'w')
        file.write(str_csv)
        file.close()
    else:
        return 0

    if SIM == True:
        file = open("reg_idx_tbl_sim.txt", 'w')

        file.write(f"{RIT.RITH.get_dw(0)+(RIT.RITH.get_dw(1)<<32):016x}\n")
        # file.write(f"{RIT.RITH.get_dw(1):016x}\n")
        file.write(f"{RIT.RITH.get_dw(2)+(RIT.RITH.get_dw(3)<<32):016x}\n")
        # file.write(f"{RIT.RITH.get_dw(3):016x}\n")

        for RITE in RIT.RITE:
            file.write(f"{RITE.get_dw(0)+(RITE.get_dw(1)<<32):016x}\n")
            # file.write(f"{RITE.get_dw(1):016x}\n")
            file.write(f"{RITE.get_dw(2)+(RITE.get_dw(3)<<32):016x}\n")
            # file.write(f"{RITE.get_dw(3):016x}\n")

        file.close()
