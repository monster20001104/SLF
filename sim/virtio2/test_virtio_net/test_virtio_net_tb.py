import sys
import random
import time

import logging
from logging.handlers import RotatingFileHandler

import cocotb
from cocotb.log import SimLog, SimLogFormatter
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Event
from cocotb.regression import TestFactory

sys.path.append('../../common')
from address_space import Pool

from bus.mlite_bus import MliteBus
from bus.beq_data_bus import BeqBus
from bus.tlp_adap_dma_bus import DmaWriteBus, DmaReadBus

from virtio_net_if import *
from virtio_net_defines import *
from virtio_net_func import cycle_pause

CLOCK_FREQ = 5


class TB(object):
    def __init__(self, cfg: Cfg, dut):
        from virtio_net_pmd import Virt
        from virtio_net import VirtioNet
        from virtio_net_ctrl import VirtioCtrl

        self.dut = dut
        self.cfg: Cfg = cfg
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, CLOCK_FREQ, units="ns").start())

        self.mem: Pool = Pool(None, 0, size=2**64, min_alloc=64)
        self.interfaces: Interfaces = Interfaces()
        self._init_interface()

        self.virtio_pmd: Virt = Virt(self)
        self.virtio_net: VirtioNet = VirtioNet(self)
        self.virtio_ctrl: VirtioCtrl = VirtioCtrl(self)

        self.worker_cr = {}

    def _init_interface(self) -> None:
        dut = self.dut
        clk = dut.clk
        rst = dut.rst
        self.interfaces.dma_if = DmaRam(DmaWriteBus.from_prefix(dut, "dma"), DmaReadBus.from_prefix(dut, "dma"), clk, rst, mem=self.mem, latency=self.cfg.dma_latency)
        self.interfaces.doorbell_if = DoorbellReqSource(DoorbellReqBus.from_prefix(dut, "doorbell_req"), clk, rst)
        self.interfaces.net2tso_if = Net2TsoSink(Net2TsoBus.from_prefix(dut, "net2tso"), clk, rst)
        self.interfaces.beq2net_if = BeqTxqMaster(BeqBus.from_prefix(dut, "beq2net"), clk, rst)
        self.interfaces.tx_qos.query_req_if = QosReqSlaver(QosReqBus.from_prefix(dut, "net_tx_qos_query_req"), clk, rst)
        self.interfaces.tx_qos.query_rsp_if = QosRspMaster(QosRspBus.from_prefix(dut, "net_tx_qos_query_rsp"), clk, rst)
        self.interfaces.tx_qos.update_if = QosUpdateSlaver(QosUpdateBus.from_prefix(dut, "net_tx_qos_update"), clk, rst)
        self.interfaces.rx_qos.query_req_if = QosReqSlaver(QosReqBus.from_prefix(dut, "net_rx_qos_query_req"), clk, rst)
        self.interfaces.rx_qos.query_rsp_if = QosRspMaster(QosRspBus.from_prefix(dut, "net_rx_qos_query_rsp"), clk, rst)
        self.interfaces.rx_qos.update_if = QosUpdateSlaver(QosUpdateBus.from_prefix(dut, "net_rx_qos_update"), clk, rst)
        self.interfaces.csr_if = MliteBusMaster(MliteBus.from_prefix(dut, "csr_if"), clk)

    async def cycle_reset(self) -> None:
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await Timer(1, "us")
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        await Timer(2, "us")

    def set_idle_generator(self, generator=None):
        if generator:
            self.interfaces.dma_if.set_idle_generator(generator)
            self.interfaces.doorbell_if.set_idle_generator(generator)
            self.interfaces.beq2net_if.set_idle_generator(generator)
            self.interfaces.tx_qos.query_rsp_if.set_idle_generator(generator)
            self.interfaces.rx_qos.query_rsp_if.set_idle_generator(generator)
            self.interfaces.csr_if.set_idle_generator(generator)

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.interfaces.dma_if.set_backpressure_generator(generator)
            self.interfaces.net2tso_if.set_backpressure_generator(generator)
            self.interfaces.tx_qos.query_req_if.set_backpressure_generator(generator)
            self.interfaces.rx_qos.query_req_if.set_backpressure_generator(generator)
            self.interfaces.csr_if.set_backpressure_generator(generator)

    def setup_virtio(self, typ: TestType, qid_list: List[int]) -> None:
        for qid in qid_list:
            vq = VirtioVq.qid2vq(qid=qid, typ=typ)
            self.virtio_pmd.create_queue(vq=vq)
            self.worker_cr[vq] = cocotb.start_soon(self.worker(vq=vq))

    async def worker(self, vq: int) -> None:
        virtq = self.virtio_pmd.virtq[vq]
        await self.virtio_pmd.start(vq=vq, avail_idx=0)
        while not virtq.finished:
            await Timer(10, "us")
            if virtq.stop_event.is_set():
                self.log.info(f"vq: {VirtioVq.vq2str(vq)} restart")
                forced_shutdown = virtq.stop_event.data
                virtq.stop_event.clear()
                await self.virtio_pmd.stop(vq=vq, forced_shutdown=forced_shutdown)
                await self.virtio_pmd.start(vq=vq, avail_idx=0)
            # self.log.error("check finished")
        self.log.error(f"vq: {VirtioVq.vq2str(vq)} worker stop")
        await self.virtio_pmd.stop(vq=vq)

    def pmd_worker(self, typ: TestType, qid_list: List[int]) -> None:
        if typ == TestType.NETTX:
            cocotb.start_soon(self.virtio_pmd.tx_check_result())
        if typ == TestType.NETRX:
            cocotb.start_soon(self.virtio_pmd.rx_check_result())
        for qid in qid_list:
            vq = VirtioVq.qid2vq(qid=qid, typ=typ)
            if typ == TestType.NETTX:
                cocotb.start_soon(self.virtio_pmd.tx_worker(vq))
            if typ == TestType.NETRX:
                cocotb.start_soon(self.virtio_pmd.rx_worker(vq))

    async def join_virtio(self, typ, qid_list):
        for qid in qid_list:
            vq = VirtioVq.qid2vq(qid, typ)
            await self.worker_cr[vq].join()
        if typ == TestType.NETRX:
            self.virtio_net.rx.doing = False
            # self.restart_cr[typ][qid].cancel()
            # await Timer(1,"us")
            # await self.virtio_pmd.stop(vq)
            # await self.virtio_pmd.destroy_queue(vq)

    def stop_worker(self, typ: TestType, qid_list: List[int]) -> None:
        async def _stop_worker(tb: TB, vq):
            virtq = tb.virtio_pmd.virtq[vq]
            while self.cfg.restart_en:
                # random_time = 3000
                random_time = random.randint(690, 800)
                await Timer(random_time, "us")
                virtq.stop_event.set(random.randint(0, 1))
                # virtq.stop_event.set(1)
                # break

        for qid in qid_list:
            vq = VirtioVq.qid2vq(qid, typ)
            cocotb.start_soon(_stop_worker(self, vq))


async def run_test(dut, cfg: Optional[Cfg] = None, idle_inserter=None, backpressure_inserter=None):
    seed = int(time.time())
    random.seed(seed)
    cfg = cfg if cfg is not None else smoke_cfg
    tb = TB(cfg, dut)

    tb.log.info(f"seed: {seed}")

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)
    await tb.cycle_reset()
    await Timer(40, "us")
    await tb.virtio_ctrl.global_reg_write()

    qid_list = random.sample(range(0, 255), cfg.q_num)

    if cfg.rx_en:
        tb.setup_virtio(TestType.NETRX, qid_list)
    if cfg.tx_en:
        tb.setup_virtio(TestType.NETTX, qid_list)

    if cfg.tx_en:
        tb.virtio_net.tx.start(qid_list)
    if cfg.rx_en:
        tb.virtio_net.rx.start(qid_list)

    if cfg.tx_en:
        tb.pmd_worker(TestType.NETTX, qid_list)
    if cfg.rx_en:
        tb.pmd_worker(TestType.NETRX, qid_list)

    if cfg.tx_en:
        tb.stop_worker(TestType.NETTX, qid_list)
    if cfg.rx_en:
        tb.stop_worker(TestType.NETRX, qid_list)

    if cfg.tx_en:
        await tb.join_virtio(TestType.NETTX, qid_list)
    if cfg.rx_en:
        await tb.join_virtio(TestType.NETRX, qid_list)

    for base, size, translate, region in tb.mem.regions:  # 查看是否所有空间都释放了
        tb.log.error(f"base:{base:x} size:{size} translate:{translate} region:{region}")

    if cfg.tx_en:
        tb.log.info(f"net_tx pps: {tb.virtio_net.tx.get_pps()}")
        tb.log.info(f"net_tx bps: {tb.virtio_net.tx.get_bps()}")

    if cfg.rx_en:
        tb.log.info(f"net_rx pps: {tb.virtio_net.rx.get_pps()}")
        tb.log.info(f"net_rx bps: {tb.virtio_net.rx.get_bps()}")

    await Timer(10, "us")


if cocotb.SIM_NAME:
    for test in [run_test]:
        factory = TestFactory(test)
        factory.add_option("cfg", [smoke_cfg])
        # factory.add_option("cfg", [Test_1Q_longchain_cfg])
        factory.add_option("idle_inserter", [cycle_pause])
        factory.add_option("backpressure_inserter", [cycle_pause])
        factory.generate_tests()


root_logger = logging.getLogger()
file_handler = RotatingFileHandler("rotating.log", mode="w")
file_handler.setFormatter(SimLogFormatter())
root_logger.addHandler(file_handler)
