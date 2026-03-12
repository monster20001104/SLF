from device import Device

class dev():
    def __init__(self, bdf):
        self.dfx_tab = None
        d = Device("0000:"+bdf)
        self.bar = d.bar[0]

    def read_data(self, addr):
        return self.bar.read(addr)

    def write_data(self, addr, data):
        return self.bar.write(addr, data)


class Tracing():
    def __init__(self, bdf, base_addr,log_file='trace.log'):
        self.d = dev(bdf)
        self.log_file = open(log_file,'w',buffering=1)
        self.switch_list = [1,1,1,1,1,1,1,1,1,0,1]
        self.read_tx_data_list = [None]*1024
        self.read_rx_data_list = [None]*1024
        self.base_addr = base_addr

    def __del__(self):
        self.log_file.close()

    def tracing_init(self,tx_flag,tx_mrd_flag,tx_mwr_flag,tx_cpl_cpld_flag,rx_flag,rx_mrd_flag,rx_mwr_flag,rx_cpl_cpld_flag,rx_cfg_flag,single_start_flag,loop_start_flag): 
        self.switch_list = [
            tx_flag          ,
            tx_mrd_flag      ,
            tx_mwr_flag      ,
            tx_cpl_cpld_flag ,
            rx_flag          ,
            rx_mrd_flag      ,
            rx_mwr_flag      ,
            rx_cpl_cpld_flag ,
            rx_cfg_flag      ,
            single_start_flag,
            loop_start_flag
            ]
        for i in range(len(self.switch_list)):
            if self.switch_list[i] == 1:
                self.d.read_data(self.base_addr+0x80000 + i*0x8)

    def tracing_stop(self):
        self.d.read_data(self.base_addr+0x80000 + 0x58)  
    
    def tracing_single_read_data(self):
        tracing_stat = self.d.read_data(self.base_addr+0x80000 + 0x100)
        rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
        tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
        print("rx_tracing_cnt:{}".format(rx_tracing_cnt), file=self.log_file) 
        print("tx_tracing_cnt:{}".format(tx_tracing_cnt), file=self.log_file)
        print("//////////////////tx_tlp://////////////////", file=self.log_file)
        if self.switch_list[0] == 1 and self.switch_list[9] == 1:
            list_index = 0
            for i in range(2*tx_tracing_cnt):
                group      = i // 4
                grp_offset = group * 0x10  
                base = self.base_addr+0xc0000 if ((i // 2) & 1 == 0) else self.base_addr+0xc2000
                offset_in_pair = (i % 2) * 0x8
                addr = base + grp_offset + offset_in_pair
                data64 = self.d.read_data(addr)
                if i%2 == 0:
                    lo64 = data64
                elif i%2 == 1:
                    hi64 = data64
                    data128 = (hi64 << 64) | lo64
                    self.read_tx_data_list[list_index] = data128
                    list_index = list_index + 1
            for i in range(tx_tracing_cnt):
                rev_data = self.read_tx_data_list[i]
                rev_time_stamp = (rev_data >> 110) & 0xffff
                rev_tlp_type = (rev_data >> 106) & 0xf
                rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                if int(rev_tlp_type) == 1:
                    print("i = {}, MRd : time_stamp = {},time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                elif int(rev_tlp_type) == 3:
                    print("i = {}, MWr : time_stamp = {},time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                elif int(rev_tlp_type) == 4:
                    print("i = {}, CPLD : time_stamp = {},time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                elif int(rev_tlp_type) == 5:
                    print("i = {}, CPL : time_stamp = {},time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
        print("//////////////////rx_tlp://////////////////", file=self.log_file)
        if self.switch_list[4] == 1 and self.switch_list[9] == 1:
            list_index = 0
            for i in range(2*rx_tracing_cnt):
                addr = self.base_addr + 0xc4000 + i*0x8
                data64 = self.d.read_data(addr)
                if i%2 == 0:
                    lo64 = data64
                elif i%2 == 1:
                    hi64 = data64
                    data128 = (hi64 << 64) | lo64
                    self.read_rx_data_list[list_index] = data128
                    list_index = list_index + 1                
            for i in range(rx_tracing_cnt):
                rev_data = self.read_rx_data_list[i]
                rev_time_stamp = (rev_data >> 110) & 0xffff
                rev_tlp_type = (rev_data >> 106) & 0xf
                rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                rev_cfg_tlp_req_id = (rev_data >> 48) & 0xffff
                rev_cfg_tlp_tag = (rev_data >> 40) & 0xff
                rev_cfg_tlp_last_be = (rev_data >> 36) & 0xf
                rev_cfg_tlp_first_be = (rev_data >> 32) & 0xf
                rev_cfg_tlp_des_id = (rev_data >> 16) & 0xffff
                rev_cfg_tlp_reg_num = (rev_data >> 2) & 0x3ff
                if int(rev_tlp_type) == 1:
                    print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                elif int(rev_tlp_type) == 3:
                    print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                elif int(rev_tlp_type) == 4:
                    print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                elif int(rev_tlp_type) == 5:
                    print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                elif int(rev_tlp_type) == 12:
                    print("i = {}, CFGRd0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                        
                elif int(rev_tlp_type) == 13:
                    print("i = {}, CFGRd1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                elif int(rev_tlp_type) == 14:
                    print("i = {}, CFGWr0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                elif int(rev_tlp_type) == 0:
                    print("i = {}, CFGWr1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)      

    def tracing_loop_read_data(self):
        tracing_stat = self.d.read_data(self.base_addr + 0x80000 + 0x100)
        rx_tracing_cnt = (tracing_stat >> 12) & 0x3ff
        rx_multiple_loop_flag_store = (tracing_stat >> 1) & 0x1
        tx_tracing_cnt = (tracing_stat >> 2) & 0x3ff
        tx_multiple_loop_flag_store = tracing_stat & 0x1   
        print("rx_tracing_cnt:{}".format(rx_tracing_cnt), file=self.log_file) 
        print("rx_multiple_loop_flag_store:{}".format(rx_multiple_loop_flag_store), file=self.log_file) 
        print("tx_tracing_cnt:{}".format(tx_tracing_cnt), file=self.log_file)
        print("tx_multiple_loop_flag_store:{}".format(tx_multiple_loop_flag_store), file=self.log_file)
        if self.switch_list[0] == 1 and self.switch_list[4] == 1 and self.switch_list[10] == 1:
            if int(tx_multiple_loop_flag_store) == 0 :
                tx_list_index = 0
                print("//////////////////tx_tlp://////////////////", file=self.log_file)
                for i in range(2*tx_tracing_cnt):
                    group      = i // 4
                    grp_offset = group * 0x10  
                    base = self.base_addr + 0xc0000 if ((i // 2) & 1 == 0) else self.base_addr + 0xc2000
                    offset_in_pair = (i % 2) * 0x8
                    addr = base + grp_offset + offset_in_pair
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_tx_data_list[tx_list_index] = data128
                        tx_list_index = tx_list_index + 1
                for i in range(tx_tracing_cnt):
                    rev_data = self.read_tx_data_list[i]
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
            if int(rx_multiple_loop_flag_store) == 0 : 
                rx_list_index = 0
                print("//////////////////rx_tlp://////////////////", file=self.log_file)
                for i in range(2*rx_tracing_cnt):
                    addr = self.base_addr + 0xc4000 + i*0x8
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_rx_data_list[rx_list_index] = data128
                        rx_list_index = rx_list_index + 1                
                for i in range(rx_tracing_cnt):
                    rev_data = self.read_rx_data_list[i]
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    rev_cfg_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cfg_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cfg_tlp_last_be = (rev_data >> 36) & 0xf
                    rev_cfg_tlp_first_be = (rev_data >> 32) & 0xf
                    rev_cfg_tlp_des_id = (rev_data >> 16) & 0xffff
                    rev_cfg_tlp_reg_num = (rev_data >> 2) & 0x3ff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 12:
                        print("i = {}, CFGRd0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                        
                    elif int(rev_tlp_type) == 13:
                        print("i = {}, CFGRd1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 14:
                        print("i = {}, CFGWr0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 0:
                        print("i = {}, CFGWr1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                  
            if int(tx_multiple_loop_flag_store) == 1 :
                tx_rev_index = 0
                tx_get_index = tx_tracing_cnt
                print("//////////////////tx_tlp://////////////////", file=self.log_file)
                for i in range(2048):
                    group      = i // 4
                    grp_offset = group * 0x10  
                    base = self.base_addr + 0xc0000 if ((i // 2) & 1 == 0) else self.base_addr + 0xc2000
                    offset_in_pair = (i % 2) * 0x8
                    addr = base + grp_offset + offset_in_pair
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_tx_data_list[tx_rev_index] = data128
                        tx_rev_index = tx_rev_index + 1
                for i in range(1024):
                    rev_data = self.read_tx_data_list[tx_get_index%1024]
                    tx_get_index = tx_get_index + 1
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)            
            if int(rx_multiple_loop_flag_store) == 1 :    
                rx_rev_index = 0
                rx_get_index = rx_tracing_cnt
                print("//////////////////rx_tlp://////////////////", file=self.log_file)
                for i in range(2048):
                    addr = self.base_addr + 0xc4000 + i*0x8
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_rx_data_list[rx_rev_index] = data128
                        rx_rev_index = rx_rev_index + 1                
                for i in range(1024):
                    rev_data = self.read_rx_data_list[rx_get_index%1024] 
                    rx_get_index = rx_get_index + 1
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    rev_cfg_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cfg_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cfg_tlp_last_be = (rev_data >> 36) & 0xf
                    rev_cfg_tlp_first_be = (rev_data >> 32) & 0xf
                    rev_cfg_tlp_des_id = (rev_data >> 16) & 0xffff
                    rev_cfg_tlp_reg_num = (rev_data >> 2) & 0x3ff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 12:
                        print("i = {}, CFGRd0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                        
                    elif int(rev_tlp_type) == 13:
                        print("i = {}, CFGRd1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 14:
                        print("i = {}, CFGWr0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 0:
                        print("i = {}, CFGWr1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                
        elif self.switch_list[0] == 1 and self.switch_list[4] == 0 and self.switch_list[10] == 1:
            if int(tx_multiple_loop_flag_store) == 0 :
                tx_list_index = 0
                print("//////////////////tx_tlp://////////////////", file=self.log_file)
                for i in range(2*tx_tracing_cnt):
                    group      = i // 4
                    grp_offset = group * 0x10  
                    base = self.base_addr + 0xc0000 if ((i // 2) & 1 == 0) else self.base_addr + 0xc2000
                    offset_in_pair = (i % 2) * 0x8
                    addr = base + grp_offset + offset_in_pair
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_tx_data_list[tx_list_index] = data128
                        tx_list_index = tx_list_index + 1
                for i in range(tx_tracing_cnt):
                    rev_data = self.read_tx_data_list[i]
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)    
            elif int(tx_multiple_loop_flag_store) == 1 :
                tx_rev_index = 0
                tx_get_index = tx_tracing_cnt
                print("//////////////////tx_tlp://////////////////", file=self.log_file)
                for i in range(2048):
                    group      = i // 4
                    grp_offset = group * 0x10  
                    base = self.base_addr + 0xc0000 if ((i // 2) & 1 == 0) else self.base_addr + 0xc2000
                    offset_in_pair = (i % 2) * 0x8
                    addr = base + grp_offset + offset_in_pair
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_tx_data_list[tx_rev_index] = data128
                        tx_rev_index = tx_rev_index + 1
                for i in range(1024):
                    rev_data = self.read_tx_data_list[tx_get_index%1024]     
                    tx_get_index = tx_get_index + 1
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)            
        elif self.switch_list[0] == 0 and self.switch_list[4] == 1 and self.switch_list[10] == 1:
            if int(tx_multiple_loop_flag_store) == 0 :
                rx_list_index = 0
                print("//////////////////rx_tlp://////////////////", file=self.log_file)
                for i in range(2*rx_tracing_cnt):
                    addr = self.base_addr + 0xc4000 + i*0x8
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_rx_data_list[rx_list_index] = data128
                        rx_list_index = rx_list_index + 1                
                for i in range(rx_tracing_cnt):
                    rev_data = self.read_rx_data_list[i]                     
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    rev_cfg_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cfg_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cfg_tlp_last_be = (rev_data >> 36) & 0xf
                    rev_cfg_tlp_first_be = (rev_data >> 32) & 0xf
                    rev_cfg_tlp_des_id = (rev_data >> 16) & 0xffff
                    rev_cfg_tlp_reg_num = (rev_data >> 2) & 0x3ff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 12:
                        print("i = {}, CFGRd0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                        
                    elif int(rev_tlp_type) == 13:
                        print("i = {}, CFGRd1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 14:
                        print("i = {}, CFGWr0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 0:
                        print("i = {}, CFGWr1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                  
            elif int(tx_multiple_loop_flag_store) == 1 :
                rx_rev_index = 0
                rx_get_index = rx_tracing_cnt
                print("//////////////////rx_tlp://////////////////", file=self.log_file)
                for i in range(2048):
                    addr = self.base_addr + 0xc4000 + i*0x8
                    data64 = self.d.read_data(addr)
                    if i%2 == 0:
                        lo64 = data64
                    elif i%2 == 1:
                        hi64 = data64
                        data128 = (hi64 << 64) | lo64
                        self.read_rx_data_list[rx_rev_index] = data128
                        rx_rev_index = rx_rev_index + 1                
                for i in range(1024):
                    rev_data = self.read_rx_data_list[rx_get_index%1024]
                    rx_get_index = rx_get_index + 1
                    rev_time_stamp = (rev_data >> 110) & 0xffff
                    rev_tlp_type = (rev_data >> 106) & 0xf
                    rev_tlp_length_dw = (rev_data >> 96) & 0x3ff
                    rev_mem_tlp_req_id = (rev_data >> 80) & 0xffff
                    rev_mem_tlp_tag = (rev_data >> 72) & 0xff
                    rev_mem_tlp_last_be = (rev_data >> 68) & 0xf
                    rev_mem_tlp_first_be = (rev_data >> 64) & 0xf
                    rev_mem_tlp_addr = (rev_data) & 0xffffffffffffffff
                    rev_cpl_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cpl_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cpl_tlp_lower_addr = (rev_data >> 32) & 0x7f
                    rev_cpl_tlp_cpl_id = (rev_data >> 16) & 0xffff
                    rev_cpl_tlp_cpl_status = (rev_data >> 13) & 0x7
                    rev_cpl_tlp_byte_count = (rev_data) & 0xfff
                    rev_cfg_tlp_req_id = (rev_data >> 48) & 0xffff
                    rev_cfg_tlp_tag = (rev_data >> 40) & 0xff
                    rev_cfg_tlp_last_be = (rev_data >> 36) & 0xf
                    rev_cfg_tlp_first_be = (rev_data >> 32) & 0xf
                    rev_cfg_tlp_des_id = (rev_data >> 16) & 0xffff
                    rev_cfg_tlp_reg_num = (rev_data >> 2) & 0x3ff
                    if int(rev_tlp_type) == 1:
                        print("i = {}, MRd : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 3:
                        print("i = {}, MWr : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},addr = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_mem_tlp_req_id),hex(rev_mem_tlp_tag),hex(rev_mem_tlp_last_be),hex(rev_mem_tlp_first_be),hex(rev_mem_tlp_addr)), file=self.log_file) 
                    elif int(rev_tlp_type) == 4:
                        print("i = {}, CPLD : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 5:
                        print("i = {}, CPL : time_stamp = {},length = {},req_id = {},tag = {},lower_addr = {},cpl_id = {},cpl_status = {},byte_count = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cpl_tlp_req_id),hex(rev_cpl_tlp_tag),hex(rev_cpl_tlp_lower_addr),hex(rev_cpl_tlp_cpl_id),hex(rev_cpl_tlp_cpl_status),hex(rev_cpl_tlp_byte_count)), file=self.log_file)
                    elif int(rev_tlp_type) == 12:
                        print("i = {}, CFGRd0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                        
                    elif int(rev_tlp_type) == 13:
                        print("i = {}, CFGRd1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 14:
                        print("i = {}, CFGWr0 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)  
                    elif int(rev_tlp_type) == 0:
                        print("i = {}, CFGWr1 : time_stamp = {},length = {},req_id = {},tag = {},last_be = {},first_be = {},des_id = {},reg_num = {}".format(i,hex(rev_time_stamp),hex(rev_tlp_length_dw),hex(rev_cfg_tlp_req_id),hex(rev_cfg_tlp_tag),hex(rev_cfg_tlp_last_be),hex(rev_cfg_tlp_first_be),hex(rev_cfg_tlp_des_id),hex(rev_cfg_tlp_reg_num)), file=self.log_file)                
