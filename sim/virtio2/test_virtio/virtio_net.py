from test_virtio_net_tb import TB
from virtio_net_tx import VirtioNetTx
from virtio_net_rx import VirtioNetRx
from virtio_blk import VirtioBLK


class VirtioNet:
    def __init__(self, tb: TB):
        self.rx: VirtioNetRx = VirtioNetRx(tb)
        self.tx: VirtioNetTx = VirtioNetTx(tb)
        self.blk: VirtioBLK = VirtioBLK(tb)
