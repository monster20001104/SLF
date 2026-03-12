#!/usr/bin/env python3
################################################################################
#  文件名称 : test_mlite_crossbar_tb.py
#  作者名称 : Feilong Yun
#  创建日期 : 2024/12/10
#  功能描述 : 
# 
#  修改记录 : 
# 
#  版本号  日期       修改人       修改内容
#  v1.0  12/10     Feilong Yun   初始化版本
################################################################################
import itertools
import logging
import os
import sys
import random
import math

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.queue import Queue
from cocotb.binary import BinaryValue
from cocotb.types import LogicArray
from cocotb.handle import Force
from cocotb.log import SimLog

sys.path.append('../../common')
from drivers.mlite_bus import MliteBusMaster
from monitors.mlite_bus import MliteBusRam
from bus.mlite_bus      import MliteBus


class TB(object):
      def __init__(self,dut,qsize,cmd_num):
           
            self.log = logging.getLogger("cocotb.tb")
            self.log.setLevel(logging.DEBUG)
            cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
            self.dut = dut
            self.q = Queue(maxsize = qsize)
            self.cmd_num = cmd_num
            self.mliteSlave0 = MliteBusRam(MliteBus.from_prefix(dut, "mlite_master0"), dut.clk, dut.rst, size=4096*16)
            self.mliteSlave1 = MliteBusRam(MliteBus.from_prefix(dut, "mlite_master1"), dut.clk, dut.rst, size=4096*16)
            self.mliteSlave2 = MliteBusRam(MliteBus.from_prefix(dut, "mlite_master2"), dut.clk, dut.rst, size=4096*16)
            self.mliteSlave3 = MliteBusRam(MliteBus.from_prefix(dut, "mlite_master3"), dut.clk, dut.rst, size=4096*16)
            self.mlitemaster = MliteBusMaster(MliteBus.from_prefix(dut, "mlite_slave") ,dut.clk)           
           
                       
      async def cycle_reset(self):      
        self.dut.rst.setimmediatevalue(0)      
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)        
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        
        
      def set_idle_generator(self, generator=None):
            if generator:
              self.mliteSlave0.set_idle_generator(generator)
              self.mliteSlave1.set_idle_generator(generator)
              self.mliteSlave2.set_idle_generator(generator)
              self.mliteSlave3.set_idle_generator(generator)
              
      def set_backpressure_generator(self, generator=None):
            if generator:
              self.mliteSlave0.set_backpressure_generator(generator)
              self.mliteSlave1.set_backpressure_generator(generator)
              self.mliteSlave2.set_backpressure_generator(generator)
              self.mliteSlave3.set_backpressure_generator(generator)


               
      async def rd_thd(self):
        for i in range(self.cmd_num) :      
              ( addr, data) = await self.q.get()
              assert data ==  await self.mlitemaster.read(addr)
             
      async def rd_thd_timeout(self):
        for i in range(self.cmd_num) :   
              (chn ,addr, data) = await self.q.get()   
              if(chn == 0 or chn == 1):
                 assert data ==  await self.mlitemaster.read(addr)
              else :
                 assert  0xdead_0000 + chn ==  await self.mlitemaster.read(addr)
               
             
async def run_test(dut,idle_inserter, backpressure_inserter):
  qsize = 4095
  round_num = qsize + 1
  cmd_num = (qsize+1)*100

  
  tb = TB(dut,qsize,cmd_num) 
  
  tb.set_idle_generator(idle_inserter)
  tb.set_backpressure_generator(backpressure_inserter)
  
  await tb.cycle_reset() 
  
  rd_cr = cocotb.start_soon(tb.rd_thd())
  
  for j in range (int(cmd_num/qsize)):
    for i in range(round_num):
      test_addr = random.randint(i*16,i*16+15) # 128 * 128 *4 = 16*4096
      test_addr = test_addr - test_addr%8 
      test_data = random.randint(0,2**64-1) 
      await tb.mlitemaster.write(test_addr,test_data,True)
      await tb.q.put((test_addr,test_data)) 
    print(j) 
    
  await rd_cr.join() 
  
  
async def run_test_timeout(dut,idle_inserter, backpressure_inserter):
  qsize = 4095
  round_num = qsize + 1
  cmd_num = (qsize+1)*100

  tb = TB(dut,qsize,cmd_num) 
  
  tb.set_idle_generator(idle_inserter)
  tb.set_backpressure_generator(backpressure_inserter)
  dut.mlite_master2_ready.value = Force(0)
  dut.mlite_master3_valid.value = Force(0)
  await tb.cycle_reset() 
  
  rd_cr = cocotb.start_soon(tb.rd_thd_timeout())
  
  for j in range (int(cmd_num/qsize)):
    for i in range(round_num):
      test_addr = random.randint(i*16,i*16+15) #   16*4096
      test_addr = test_addr - test_addr%8 
      test_data = random.randint(0,2**64-1) 
      
      if test_addr < 4096*4:
          chn = 0
          await tb.mlitemaster.write(test_addr,test_data,True)
      elif test_addr < 4096*8:
          chn = 1
          await tb.mlitemaster.write(test_addr,test_data,True)
      elif test_addr < 4096*12 :
          chn = 2
      else :
          chn = 3
          await tb.mlitemaster.write(test_addr,test_data,True)
              
      await tb.q.put((chn ,test_addr,test_data)) 
    print(j) 
    
  await rd_cr.join() 
   
          
def cycle_pause():
    seed = [1 if i < 300 else 0 for i in range(1000)]
    random.shuffle(seed)
    seed = seed + [1 for _ in range(100)]
    return itertools.cycle(seed)
              
if cocotb.SIM_NAME:
    
    for test in [run_test ,run_test_timeout]:

        factory = TestFactory(test)
        factory.add_option("idle_inserter", [None, cycle_pause])
        factory.add_option("backpressure_inserter", [None, cycle_pause])
        factory.generate_tests()            

            
  
    
    
    

     
    


    

    
    

