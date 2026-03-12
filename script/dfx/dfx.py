#!/usr/bin/python3
# -*- coding: utf-8 -*-
import argparse
import sys
import time
from dfx_base import Dfx, dev
from beq_dfx_tbl import dfx_beq_queue, dfx_dpu_status
from beq_dfx_tbl import dfx_beq_common_err, dfx_beq_desc_engine_err, dfx_beq_rxq_err, dfx_beq_txq_err, dfx_beq_loopback_err, pcie_switch
from beq_dfx_tbl import dfx_beq_common_status, dfx_beq_desc_engine_status, dfx_beq_rxq_status, dfx_beq_txq_status, dfx_beq_loopback_status
from beq_dfx_tbl import dfx_soc_pcie_perf,dfx_host_pcie_perf,dfx_skp_cnt, dfx_host_pcie_aer_uncorr_sts, dfx_host_pcie_aer
from beq_dfx_tbl import sgdma_err, emu_err, host_tlp_adaptor_arbiter_err, soc_tlp_adaptor_arbiter_err, dfx_soc_pcie_err, dfx_host_pcie_err, pcie_switch_err
from beq_dfx_tbl import sgdma_status, emu_status, host_tlp_adaptor_arbiter_status, soc_tlp_adaptor_arbiter_status, emu_perf,dfx_beq_perf
from beq_dfx_tbl import dfx_host_pcie_stat, dfx_soc_pcie_stat, dfx_loop_host_pcie_stat, dfx_loop_host_pcie_err, qos_err, qos_status
from virtio2_dfx_tbl import dfx_virtio_desc_eng_err, dfx_virtio_desc_eng_status
from virtio2_dfx_tbl import dfx_virtio_blk_downstream_err, dfx_virtio_blk_downstream_status, dfx_tso_csum_err, dfx_tso_csum_status
from virtio2_dfx_tbl import dfx_virtio_idx_engine_err, dfx_virtio_idx_engine_status, dfx_virtio_avail_ring_err, dfx_virtio_avail_ring_status
from virtio2_dfx_tbl import dfx_virtio_nettx_err,dfx_virtio_nettx_status,dfx_virtio_netrx_err,dfx_virtio_netrx_status
from virtio2_dfx_tbl import dfx_virtio_dump_queue
from virtio2_dfx_tbl import dfx_virtio_used_err,dfx_virtio_used_status
from virtio2_dfx_tbl import dfx_virtio_blk_upstream_err,dfx_virtio_blk_upstream_status
from virtio2_dfx_tbl import dfx_virtio_ctx_err, dfx_virtio_ctx_status
from virtio2_dfx_tbl import *

class beq_dfx():
  def summary(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x280000, dfx_tab=dfx_host_pcie_aer_uncorr_sts)
    print("host_pcie_aer_uncorr_sts:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x1800000+0x640000, dfx_tab=dfx_virtio_desc_eng_err)
    print("virtio_desc_eng:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0xc00000, dfx_tab=dfx_beq_common_err)
    print("beq_common:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0xc01000, dfx_tab=dfx_beq_desc_engine_err)
    print("desc_engine:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0xc02000, dfx_tab=dfx_beq_rxq_err)
    print("beq_rxq:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0xc03000, dfx_tab=dfx_beq_txq_err)
    print("beq_txq:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0xFFF000, dfx_tab=dfx_beq_loopback_err)
    print("beq_loopback:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x500000, dfx_tab=sgdma_err)
    print("sgdma:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x400000, dfx_tab=pcie_switch_err)
    print("pcie_switch:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x1400000, dfx_tab=emu_err)
    print("emu:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x600000, dfx_tab=host_tlp_adaptor_arbiter_err)
    print("host_tlp_adaptor_arbiter:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x700000, dfx_tab=soc_tlp_adaptor_arbiter_err)
    print("soc_tlp_adaptor_arbiter:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x200000, dfx_tab=dfx_host_pcie_err)
    print("host_tlp_adaptor:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x300000, dfx_tab=dfx_soc_pcie_err)
    print("soc_tlp_adaptor:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x200000, dfx_tab=dfx_loop_host_pcie_err)
    print("dfx_loop_host_pcie:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x2300000, dfx_tab=qos_err)
    print("qos:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x1800000+0x6e0000, dfx_tab=dfx_virtio_blk_downstream_err)
    print("virtio_blk_downstream:")
    dfx.traverse_tbl(hidden=True)
    dfx = Dfx(bdf=bdf, base_addr=0x2400000, dfx_tab=dfx_tso_csum_err)
    print("tso_csum:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x600000, dfx_tab=dfx_virtio_idx_engine_err)
    print("avail_idx:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x620000, dfx_tab=dfx_virtio_avail_ring_err)
    print("avail_ring:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x660000, dfx_tab=dfx_virtio_rx_buf_err)
    print("dfx_virtio_rx_buf:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x680000, dfx_tab=dfx_virtio_netrx_err)
    print("netrx:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x6a0000, dfx_tab=dfx_virtio_nettx_err)
    print("nettx:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x6c0000, dfx_tab=dfx_virtio_blk_desc_engine_err)
    print("dfx_virtio_blk_desc_engine:")
    dfx.traverse_tbl(hidden=True)


    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x700000, dfx_tab=dfx_virtio_blk_upstream_err)
    print("virtio_blk_upstream:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x720000, dfx_tab=dfx_virtio_used_err)
    print("virtio_used:")
    dfx.traverse_tbl(hidden=True)

    dfx = Dfx(bdf=bdf, base_addr=0x1800000 + 0x760000, dfx_tab=dfx_virtio_ctx_err)
    print("virtio_ctx:")
    dfx.traverse_tbl(hidden=True)

  def host_pcie_aer(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x280000, dfx_tab=dfx_host_pcie_aer_uncorr_sts)
    print("host_pcie_aer_uncorr_sts:")
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x280000, dfx_tab=dfx_host_pcie_aer)
    print("host_pcie_aer_others:")
    dfx.traverse_tbl()

  def virtio_desc_eng(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x1800000+0x640000, dfx_tab=dfx_virtio_desc_eng_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x1800000+0x640000, dfx_tab=dfx_virtio_desc_eng_status)
    dfx.traverse_tbl()
  def beq_lo(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0xFFF000, dfx_tab=dfx_beq_loopback_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0xFFF000, dfx_tab=dfx_beq_loopback_status)
    dfx.traverse_tbl()
  def beq_dump_queue(self, bdf, qid=0, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x800000, dfx_tab=dfx_beq_queue)
    print("beq rxq(qid:{})".format(qid))
    dfx.traverse_tbl(idx=qid*2, stride=0x400, mask=0)
    print("beq txq(qid:{})".format(qid))
    dfx.traverse_tbl(idx=qid*2+1, stride=0x400, mask=1)
  def beq_common(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0xc00000, dfx_tab=dfx_beq_common_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0xc00000, dfx_tab=dfx_beq_common_status)
    dfx.traverse_tbl()
  def beq_desc_engine(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0xc01000, dfx_tab=dfx_beq_desc_engine_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0xc01000, dfx_tab=dfx_beq_desc_engine_status)
    dfx.traverse_tbl()
  def beq_rxq(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0xc02000, dfx_tab=dfx_beq_rxq_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0xc02000, dfx_tab=dfx_beq_rxq_status)
    dfx.traverse_tbl()
  def beq_txq(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0xc03000, dfx_tab=dfx_beq_txq_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0xc03000, dfx_tab=dfx_beq_txq_status)
    dfx.traverse_tbl()

  def dpu_status(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x0, dfx_tab=dfx_dpu_status)
    dfx.traverse_tbl()

  def pcie_switch(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x400000, dfx_tab=pcie_switch)
    dfx.traverse_tbl()
  
  def sgdma(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x500000, dfx_tab=sgdma_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x500000, dfx_tab=sgdma_status)
    dfx.traverse_tbl()

  def emu(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x1400000, dfx_tab=emu_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x1400000, dfx_tab=emu_status)
    dfx.traverse_tbl()

  def emu_perf(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x1400000, dfx_tab=emu_perf)
    dfx.traverse_tbl()

  def host_tlp_adaptor_arbiter(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x600000, dfx_tab=host_tlp_adaptor_arbiter_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x600000, dfx_tab=host_tlp_adaptor_arbiter_status)
    dfx.traverse_tbl()

  def soc_tlp_adaptor_arbiter(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x700000, dfx_tab=soc_tlp_adaptor_arbiter_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x700000, dfx_tab=soc_tlp_adaptor_arbiter_status)
    dfx.traverse_tbl()

  def soc_pcie_perf(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x300000, dfx_tab=dfx_soc_pcie_perf)
    dfx.traverse_tbl()
    
  def host_pcie_perf(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x200000, dfx_tab=dfx_host_pcie_perf)
    dfx.traverse_tbl()

  def host_pcie_stat(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x200000, dfx_tab=dfx_host_pcie_stat)
    dfx.traverse_tbl()

  def loop_host_pcie_stat(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x200000, dfx_tab=dfx_loop_host_pcie_stat)
    dfx.traverse_tbl()

  def soc_pcie_stat(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x300000, dfx_tab=dfx_soc_pcie_stat)
    dfx.traverse_tbl()

  def beq_perf(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0xc00000, dfx_tab=dfx_beq_perf)
    dfx.traverse_tbl()

  def pcie_skp_cnt(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x0, dfx_tab=dfx_skp_cnt)
    dfx.traverse_tbl()

  def qos(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x2300000, dfx_tab=qos_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x2300000, dfx_tab=qos_status)
    dfx.traverse_tbl()

  def virtio_blk_downstream(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x1800000+0x6e0000, dfx_tab=dfx_virtio_blk_downstream_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x1800000+0x6e0000, dfx_tab=dfx_virtio_blk_downstream_status)
    dfx.traverse_tbl()

  def tso_csum(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x2400000, dfx_tab=dfx_tso_csum_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr=0x2400000, dfx_tab=dfx_tso_csum_status)
    dfx.traverse_tbl()

  def virtio_idx_engine(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x600000, dfx_tab=dfx_virtio_idx_engine_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x600000, dfx_tab=dfx_virtio_idx_engine_status)
    dfx.traverse_tbl()

  def virtio_avail_ring(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x620000, dfx_tab=dfx_virtio_avail_ring_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x620000, dfx_tab=dfx_virtio_avail_ring_status)
    dfx.traverse_tbl()
  
  def virtio_netrx(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x680000, dfx_tab=dfx_virtio_netrx_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x680000, dfx_tab=dfx_virtio_netrx_status)
    dfx.traverse_tbl()

  def virtio_nettx(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x6a0000, dfx_tab=dfx_virtio_nettx_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x6a0000, dfx_tab=dfx_virtio_nettx_status)
    dfx.traverse_tbl()

  def virtio_blk_upstream(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x700000, dfx_tab=dfx_virtio_blk_upstream_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x700000, dfx_tab=dfx_virtio_blk_upstream_status)
    dfx.traverse_tbl()

  def virtio_used(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x720000, dfx_tab=dfx_virtio_used_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x720000, dfx_tab=dfx_virtio_used_status)
    dfx.traverse_tbl()

  def virtio_ctx(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x760000, dfx_tab=dfx_virtio_ctx_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x760000, dfx_tab=dfx_virtio_ctx_status)
    dfx.traverse_tbl()

  def virtio_dump_queue(self, bdf, fe_type, qid=0, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr=0x1800000, dfx_tab=dfx_virtio_dump_queue)
    print("virtio {}(qid:{}):".format(fe_type, qid))
    if fe_type == "nettx":
      idx = qid * 4 + 0
      dfx.traverse_tbl(idx=idx, stride=0x1000, mask=1)
    elif fe_type == "netrx":
      idx = qid * 4 + 1
      dfx.traverse_tbl(idx=idx, stride=0x1000, mask=1)
    else:
      idx = qid * 4 + 2
      dfx.traverse_tbl(idx=idx, stride=0x1000, mask=2)

  def virtio_rx_buf(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x660000, dfx_tab=dfx_virtio_rx_buf_err)
    dfx.traverse_tbl()

    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x660000, dfx_tab=dfx_virtio_rx_buf_status)
    dfx.traverse_tbl()

    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x660000, dfx_tab=dfx_virtio_rx_buf_drop_total)
    dfx.traverse_tbl()

  def virtio_rx_buf_drop_info(self, bdf, qid = 0, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x660000, dfx_tab=dfx_virtio_rx_buf_ram_q)
    idx = qid
    dfx.traverse_tbl(idx=idx, stride=0x8)

  def virtio_blk_desc_engine(self, bdf, **kwargs):
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x6c0000, dfx_tab=dfx_virtio_blk_desc_engine_err)
    dfx.traverse_tbl()
    dfx = Dfx(bdf=bdf, base_addr= 0x1800000 + 0x6c0000, dfx_tab=dfx_virtio_blk_desc_engine_status)
    dfx.traverse_tbl()

  def reg_write(self, bdf, **kwargs): 
    d = dev(bdf)
    d.write_data(kwargs["addr"], kwargs["data"])
  def reg_read(self, bdf, **kwargs):
    d = dev(bdf)
    print(hex(d.read_data(kwargs["addr"])))

if __name__=="__main__":
  dfx = beq_dfx()
  methods = [m_name for m_name in dir(dfx) if m_name[0:2] != '__']
  parser = argparse.ArgumentParser(description=(
        "BEQ / Virtio / PCIe debug utility.\n"
        "Used to dump status/error registers, queue state, performance counters, "
        "and perform direct MMIO register read/write via PCIe BDF."
    )
  )
  parser.add_argument("-bdf", "--bdf", type=str, default='01:00.0', help = (
        "PCIe device BDF in Bus:Device.Function format.\n"
        "Example: 01:00.0"
    )
  )
  parser.add_argument("-m", "--method", type=str, default='summary', choices=methods, help=(
        "Debug operation to execute.\n"
        "Examples:\n"
        "  summary               - Dump all major error/status blocks\n"
        "  beq_rxq               - Dump BEQ RXQ error/status\n"
        "  virtio_dump_queue     - Dump Virtio queue state\n"
        "  reg_read / reg_write  - Direct MMIO register access"
    )
  )
  parser.add_argument("-qid", "--qid", type=int, default=0, help=(
        "Queue ID used by queue-related debug methods.\n"
        "Valid for: beq_dump_queue, virtio_dump_queue, virtio_rx_buf_drop_info, etc.\n"
        "Default: 0"
    )
  )
  parser.add_argument("-fe_type", "--fe_type", type=str, default="nettx", choices=["nettx", "netrx", "blk"], help=(
        "Virtio frontend type.\n"
        "nettx : Virtio-net TX queue\n"
        "netrx : Virtio-net RX queue\n"
        "blk   : Virtio-blk queue\n"
        "Used only by virtio_dump_queue."
    )
  )
  parser.add_argument("-addr", "--addr", type=lambda x: int(x, 0), default=0, help=(
        "MMIO register address offset.\n"
        "Supports decimal or hex (prefix with 0x).\n"
        "Required by: reg_read, reg_write.\n"
        "Example: 0x1800640"
    )
  )
  parser.add_argument("-data", "--data", type=lambda x: int(x, 0), default=0, help=(
        "Data value to write to MMIO register.\n"
        "Supports decimal or hex (prefix with 0x).\n"
        "Used only by: reg_write.\n"
        "Example: 0x1"
    )
  )
  args = parser.parse_args()
  getattr(dfx, args.method)(args.bdf, qid=args.qid, fe_type=args.fe_type, addr=args.addr, data=args.data)