from test_virtio_net_tb import TB
from virtio_net_tx import VirtioNetTx
from virtio_net_rx import VirtioNetRx


class VirtioNet:
    def __init__(self, tb: TB):
        self.rx = VirtioNetRx(tb)
        self.tx = VirtioNetTx(tb)
