import collections
from device import Device
import numbers

class dev():
  def __init__(self, bdf):
    self.dfx_tab = None
    d = Device("0000:"+bdf)
    self.bar = d.bar[0]

  def read_data(self, addr):
      return self.bar.read(addr)

  def write_data(self, addr, data):
      return self.bar.write(addr, data)


class Dfx():
  def __init__(self, bdf, base_addr, dfx_tab):
    self.d = dev(bdf)
    self.base_addr = base_addr
    self.dfx_tab = dfx_tab

    self.name2addr = {}
    for key in self.dfx_tab.keys():
      names = self.dfx_tab[key].keys()
      for name in names:
        self.name2addr[name] = key


    
  def read_element(self, name, idx=None):
    pass
  
  def virtio_dfx_info(self, gid, write=True):
    #1. write idx to reg
    if write:
        print("write addr : data ", hex(self.base_addr + 0x400), gid)
        self.d.write_data(self.base_addr + 0x400, gid)

    #2. read info
    for offset in self.dfx_tab.keys():
      reg_data = self.d.read_data(self.base_addr + offset)
      #print("read addr : ", hex(self.base_addr + offset))
      descs = self.dfx_tab[offset]
      for name in descs.keys():
        desc = descs[name]
        bits_ofs = desc["bits_ofs"]
        bits_len = desc["bits_len"]
        data = reg_data >> bits_ofs * ((1<<bits_len) - 1)
        print("{}:{}".format(name, hex(data)))

  def traverse_tbl(self, idx=None, stride=None, mask=None, hidden=False):
    if idx != None and stride == None:
      raise ValueError("stride is None")
    for offset in self.dfx_tab.keys():
      descs = self.dfx_tab[offset]
      if idx != None:
        reg_data = self.d.read_data(self.base_addr+idx*stride+offset)
      else:
        reg_data = self.d.read_data(self.base_addr+offset)
      for name in descs.keys():
        desc = descs[name]
        if mask == None or "mask" not in desc.keys() or mask == desc["mask"]:
          if "bits_ofs" in desc.keys():
            bits_ofs = desc["bits_ofs"]
          else:
            bits_ofs = 0
          if "bits_len" in desc.keys():
            bits_len = desc["bits_len"]
          else:
            bits_len = 0
          if "enum" in desc.keys():
            enum = desc["enum"]
          else:
            enum = {}
          data = reg_data >> bits_ofs & ((1<<bits_len)-1)
          if "transfer_function" in desc.keys():
            data = desc["transfer_function"](data)
          if data in enum.keys():
            print("{}:{}".format(name, enum[data]))
          else:
            if not hidden or (hidden and data != 0):
              if type(data) == int:
                print("{}:{}".format(name, hex(data)))
              else:
                print("{}:{}".format(name, data))

          
          
