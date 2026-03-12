import logging

from cocotb.triggers import RisingEdge, Timer


class I2cMaster:

    def __init__(self, sda=None, sda_o=None, scl=None, scl_o=None, speed=400e3, *args, **kwargs):
        self.log = logging.getLogger(f"cocotb.{sda._path}")
        self.sda = sda
        self.sda_o = sda_o
        self.scl = scl
        self.scl_o = scl_o
        self.speed = speed

        super().__init__(*args, **kwargs)

        self.bus_active = False

        if self.sda_o is not None:
            self.sda_o.setimmediatevalue(1)
        if self.scl_o is not None:
            self.scl_o.setimmediatevalue(1)

        self.log.info("I2C master configuration:")
        self.log.info("  Speed: %d bps", self.speed)

        self._bit_t = Timer(int(1e9/self.speed), 'ns')
        self._half_bit_t = Timer(int(1e9/self.speed/2), 'ns')

    def _set_sda(self, val):
        if self.sda_o is not None:
            self.sda_o.value = val
        else:
            self.sda.value = val
            # self.sda <= BinaryValue('z') if val else 0

    def _set_scl(self, val):
        if self.scl_o is not None:
            self.scl_o.value = val
        else:
            self.scl.value = val
            # self.scl <= BinaryValue('z') if val else 0

    async def send_start(self):
        if self.bus_active:
            self._set_sda(1)
            await self._half_bit_t
            self._set_scl(1)
            while not self.scl.value:
                await RisingEdge(self.scl)
            await self._half_bit_t

        self._set_sda(0)
        await self._half_bit_t
        self._set_scl(0)
        await self._half_bit_t

        self.bus_active = True

    async def send_stop(self):
        if not self.bus_active:
            return

        self._set_sda(0)
        await self._half_bit_t
        self._set_scl(1)
        while not self.scl.value:
            await RisingEdge(self.scl)
        await self._half_bit_t
        self._set_sda(1)
        await self._half_bit_t

        self.bus_active = False

    async def send_bit(self, b):
        if not self.bus_active:
            self.send_start()
        self._set_sda(bool(b))
        await self._half_bit_t
        self._set_scl(1)
        while not self.scl.value:
            await RisingEdge(self.scl)
        await self._bit_t
        self._set_scl(0)
        await self._half_bit_t

    async def recv_bit(self):
        if not self.bus_active:
            self.send_start()

        self._set_sda(1)
        await self._half_bit_t
        b = bool(self.sda.value.integer)
        self._set_scl(1)
        while not self.scl.value:
            await RisingEdge(self.scl)
        await self._bit_t
        self._set_scl(0)
        await self._half_bit_t

        return b

    async def send_byte(self, b):
        for i in range(8):
            await self.send_bit(b & (1 << 7-i))
        return await self.recv_bit()

    async def recv_byte(self, ack):
        b = 0
        for i in range(8):
            b = (b << 1) | await self.recv_bit()
        await self.send_bit(ack)
        return b

    async def write(self, addr, data):
        self.log.info("Write %s to device at I2C address 0x%02x", data, addr)
        await self.send_start()
        ack = await self.send_byte((addr << 1) | 0)
        if ack:
            self.log.info("Got NACK")
        for b in data:
            ack = await self.send_byte(b)
            if ack:
                self.log.info("Got NACK")

    async def read(self, addr, count):
        self.log.info("Read %d bytes from device at I2C address 0x%02x", count, addr)
        await self.send_start()
        ack = await self.send_byte((addr << 1) | 1)
        if ack:
            self.log.info("Got NACK")
        data = bytearray()
        for k in range(count):
            data.append(await self.recv_byte(k == count-1))
        return data
