from scapy.packet import Raw
from scapy.volatile import RandMAC, RandString
from scapy.layers.inet import TCP, UDP, IP, ICMP
from scapy.layers.inet6 import IPv6, ICMPv6Unknown
from scapy.layers.l2 import Dot1Q, Ether, ARP

import random


class Config:
    def __init__(self, name="Config"):
        self._name = name
        self._data = {}
        self._getmode = "error"

    def __setattr__(self, name, value):
        if name.startswith('_'):
            object.__setattr__(self, name, value)
        else:
            self._data[name] = value

    def __getattr__(self, name):
        if name.startswith('_'):
            return object.__getattribute__(self, name)
        if name not in self._data and self._getmode == "error":
            raise AttributeError(f"'{self._name}'has no'{name}'")
        return self._data.get(name)

    def __delattr__(self, name):
        try:
            del self._data[name]
        except KeyError:
            raise AttributeError(f"'{self._name}'对象无属性'{name}'")

    def update(self, other):
        if not isinstance(getattr(other, '_data', None), dict):
            raise TypeError("需传入包含字典类型_data属性的对象")
        self._data.update(other._data.copy())

    def __str__(self):
        return self._to_string()

    def _to_string(self, indent=0):
        prefix = '    ' * indent
        if indent == 0:
            result = [f"{prefix}{self._name}:"]
        else:
            result = []
        for key, value in self._data.items():
            if isinstance(value, Config):
                result.append(f"{prefix}    {key}_{value._name}")
                result.append(value._to_string(indent + 1))
            else:
                result.append(f"{prefix}    {key}: {value}")
        return '\n'.join(result)


class Eth_Pkg_Cfg(Config):
    def __init__(self, name="EthPkgConfig"):
        super().__init__(name)
        self._data = {
            "test_mode": "normal",  # bps pps
            "random_vlan": 0.5,
            "random_ipv4_ihl": 0.1,
            "random_net_csum_err": 0.1,
            "random_trans_csum_err": 0.1,
            "payload_max": 1500,
            "net_ipv4_en": True,
            "random_frag": 0.1,
            "net_ipv6_en": True,
            "net_arp_en": True,
            "net_raw_en": True,
            "trans_tcp_en": True,
            "trans_udp_en": True,
            "random_udp_chksum_zero": 0.01,
            "trans_icmpv4_en": True,
            "trans_icmpv6_en": True,
        }


def gen_vlan(eth_cfg, eth_info, eth_pkt):
    """随机生成vlan(可能无效)"""
    if random.random() < eth_cfg.random_vlan:
        prio = random.randint(0, 7)
        dei = random.randint(0, 1)
        vlan = random.randint(0, 4095)
        try:
            dot1q = Dot1Q(prio=prio, dei=dei, vlan=vlan)
        except Exception as e:
            raise ValueError(f"生成Dot1Q失败，参数: prio={prio}, dei={dei}, vlan={vlan}") from e
        eth_pkt /= dot1q

        vlan_cls = Config("Vlan")
        vlan_cls.vlan = vlan
        eth_info.vlan = vlan_cls

    return eth_cfg, eth_info, eth_pkt


def gen_ipv4(eth_cfg):
    """随机生成IPv4(可能无效)"""
    ipv4_info = Config("ipv4_info")
    version = random.randint(0, 15)  # 随机版本
    tos = random.randint(0, 255)  # 无效服务类型
    id = random.randint(0, 65535)  # 随机标识
    flags = random.randint(0, 7)
    frag = random.randint(0, 8191)
    if random.random() < (1 - eth_cfg.random_frag):
        flags &= 0b110
        frag = 0

    ttl = random.randint(0, 255)
    src = ".".join(map(str, [random.randint(0, 255) for _ in range(4)]))
    dst = ".".join(map(str, [random.randint(0, 255) for _ in range(4)]))
    if random.random() < eth_cfg.random_ipv4_ihl:
        options = bytes([random.randint(0, 255) for _ in range(4 * random.randint(0, 10))])
    else:
        options = ""
    try:
        ipv4 = IP(
            version=version,
            tos=tos,
            id=id,
            flags=flags,
            frag=frag,
            ttl=ttl,
            src=src,
            dst=dst,
            options=options,
        )
    except Exception as e:
        raise ValueError(f"生成IPv4失败，参数: version={version}, tos={tos}, id={id}, flags={flags}, frag={frag}, ttl={ttl}, src={src}, dst={dst}, options长度={len(options)}") from e

    # 需要的时候再提取
    ipv4_info.flags = ipv4.flags
    ipv4_info.frag = ipv4.frag
    ipv4_info.csum_err = False
    return ipv4_info, ipv4


def gen_ipv6(eth_cfg):
    """随机生成IPv6(可能无效)"""
    ipv6_info = Config("ipv6_info")
    # 随机生成IPv6头部字段
    version = random.randint(0, 15)  # 随机版本
    tc = random.randint(0, 255)  # 流量类别
    fl = random.randint(0, 0xFFFFFF)  # 流标签
    hlim = random.randint(0, 255)  # 跳数限制

    # 生成随机IPv6地址 (简化版)
    src = ":".join(["%x" % random.randint(0, 0xFFFF) for _ in range(8)])
    dst = ":".join(["%x" % random.randint(0, 0xFFFF) for _ in range(8)])

    try:
        ipv6 = IPv6(
            version=version,
            tc=tc,
            fl=fl,
            hlim=hlim,
            src=src,
            dst=dst,
        )
    except Exception as e:
        raise ValueError(f"生成IPv6失败，参数: version={version}, tc={tc}, fl={fl}, hlim={hlim}, src={src}, dst={dst}") from e

    return ipv6_info, ipv6


def gen_arp(eth_cfg):
    """随机生成ARP包(可能无效,但字段长度与类型匹配)"""
    arp_info = Config("arp_info")
    
    # 硬件类型(常见0x0001=以太网)
    hwtype = random.randint(0, 65535)
     # 硬件地址长度(字节,以太网为6)
    hwlen = random.randint(0, 255)
    # 协议类型(常见0x0800=IPv4,0x86dd=IPv6)
    ptype = random.randint(0, 65535)
    # 协议地址长度(字节,IPv4=4,IPv6=16)
    plen = random.randint(0, 255)
    # 操作码(常见1=请求,2=应答)
    op = random.randint(0, 65535)

    # 2. 生成硬件地址(hwsrc/hwdst)：长度必须等于hwlen
    def gen_hw_addr(length):
        """生成指定长度(字节)的硬件地址,格式化为冒号分隔的十六进制字符串"""
        if length <= 0:
            return ""  # 长度为0时返回空
        # 生成length个随机字节(0-255),转换为十六进制并拼接
        bytes_list = [random.randint(0, 255) for _ in range(length)]
        return ":".join(f"{b:02x}" for b in bytes_list)
    
    hwsrc = gen_hw_addr(hwlen)
    hwdst = gen_hw_addr(hwlen)

    # 3. 生成协议地址(psrc/pdst)：根据ptype和plen动态生成
    def gen_proto_addr(ptype, plen):
        """根据协议类型和长度生成对应的协议地址"""
        if plen <= 0:
            return ""  # 长度为0时返回空
        
        # 情况1：IPv4(ptype=0x0800 且 plen=4)
        if ptype == 0x0800 and plen == 4:
            # 生成4个0-255的数字,格式化为"x.x.x.x"
            return ".".join(map(str, [random.randint(0, 255) for _ in range(4)]))
        
        # 情况2：IPv6(ptype=0x86dd 且 plen=16)
        elif ptype == 0x86dd and plen == 16:
            # 生成8组16进制数(每组4位),格式化为"xxxx:xxxx:..."
            groups = [random.randint(0, 0xffff) for _ in range(8)]
            return ":".join(f"{g:04x}" for g in groups)
        
        # 其他情况：生成plen字节的随机字节串(格式化为冒号分隔的十六进制)
        else:
            bytes_list = [random.randint(0, 255) for _ in range(plen)]
            return ":".join(f"{b:02x}" for b in bytes_list)
    
    psrc = gen_proto_addr(ptype, plen)
    pdst = gen_proto_addr(ptype, plen)

    try:
        arp = ARP(
            hwtype=hwtype,
            ptype=ptype,
            hwlen=hwlen,
            plen=plen,
            op=op,
            hwsrc=hwsrc,
            hwdst=hwdst,
            psrc=psrc,
            pdst=pdst,
        )
    except Exception as e:
        raise ValueError(f"生成ARP失败，参数: hwtype={hwtype}, ptype={ptype}, hwlen={hwlen}, plen={plen}, op={op}, hwsrc={hwsrc}, hwdst={hwdst}, psrc={psrc}, pdst={pdst}") from e

    return arp_info, arp


def gen_raw(eth_cfg):
    """随机生成raw(可能无效)"""
    raw_info = Config("raw_info")
    max_payload = max(0, eth_cfg.payload_max)
    min_payload = 0
    if eth_cfg.test_mode == "pps":
        max_payload = 0
    elif eth_cfg.test_mode == "bps":
        max_payload = max(0, eth_cfg.bps_base_len)
        min_payload = max_payload
    payload_len = random.randint(min_payload, max_payload)
    load = bytes([random.randint(0, 255) for _ in range(payload_len)])
    try:
        raw = Raw(load=load)
    except Exception as e:
        raise ValueError(f"生成Raw失败，参数: payload_len={payload_len}, load长度={len(load)}") from e

    return raw_info, raw


def gen_network(eth_cfg, eth_info, eth_pkt):
    network_choices = []

    if eth_cfg.net_ipv4_en and eth_cfg.test_mode != "pps":
        network_choices.append(('ipv4', lambda: gen_ipv4(eth_cfg)))
    if eth_cfg.net_ipv6_en and eth_cfg.test_mode != "pps":
        network_choices.append(('ipv6', lambda: gen_ipv6(eth_cfg)))
    if eth_cfg.net_arp_en and eth_cfg.test_mode == "normal":
        network_choices.append(('arp', lambda: gen_arp(eth_cfg)))
    if eth_cfg.net_raw_en or eth_cfg.test_mode == "pps":
        network_choices.append(('raw', lambda: gen_raw(eth_cfg)))

    if not network_choices:
        network_choices.append(('raw', lambda: gen_raw(eth_cfg)))

    net_type, net_layer = random.choice(network_choices)
    net_info, net_pkt = net_layer()
    eth_info.net_type = net_type
    eth_info.net_info = net_info
    eth_pkt /= net_pkt
    
    if Raw in eth_pkt:
        # if eth_cfg.test_mode == "bps":
        #     eth_cfg.net_len = 0
        # else:
        eth_pkt[Ether].type = len(eth_pkt[Raw])
    if IP in eth_pkt:
        eth_cfg.net_len = len(eth_pkt[IP])
    if IPv6 in eth_pkt:
        eth_cfg.net_len = len(eth_pkt[IPv6])

    return eth_cfg, eth_info, eth_pkt


def gen_tcp(eth_cfg):
    tcp_info = Config("tcp_info")
    sport = random.randint(0, 65535)
    dport = random.randint(0, 65535)
    seq = random.randint(0, 0xFFFFFFFF)
    ack = random.randint(0, 0xFFFFFFFF)
    reserved = random.randint(0, 7)
    flags = random.randint(0, 0xFF)
    window = random.randint(0, 65535)
    urgptr = random.randint(0, 65535)
    options = [(random.randint(0, 255), bytes([random.randint(0, 255) for _ in range(random.randint(0, 3))])) for _ in range(random.randint(0, 5))]
    try:
        tcp = TCP(
            sport=sport,
            dport=dport,
            seq=seq,
            ack=ack,
            reserved=reserved,
            flags=flags,
            window=window,
            urgptr=urgptr,
            options=options,
        )
    except Exception as e:
        raise ValueError(f"生成TCP失败，参数: sport={sport}, dport={dport}, seq={seq}, ack={ack}, reserved={reserved}, flags={flags}, window={window}, urgptr={urgptr}, options数量={len(options)}") from e

    if eth_cfg.test_mode == "bps":
        max_payload = max(0, eth_cfg.bps_base_len - eth_cfg.net_len - len(tcp))
        min_payload = max_payload
    else:
        max_payload = max(0, eth_cfg.payload_max - eth_cfg.net_len - len(tcp))
        min_payload = 0
    tcp /= str(RandString(size=random.randint(min_payload, max_payload)))
    tcp_info.csum_err = False
    return tcp_info, tcp


def gen_udp(eth_cfg):
    udp_info = Config("udp_info")
    # 随机生成UDP头部字段
    sport = random.randint(0, 65535)
    dport = random.randint(0, 65535)

    try:
        udp = UDP(sport=sport, dport=dport)
    except Exception as e:
        raise ValueError(f"生成UDP失败，参数: sport={sport}, dport={dport}") from e

    # 计算有效载荷长度
    if eth_cfg.test_mode == "bps":
        max_payload = max(0, eth_cfg.bps_base_len - eth_cfg.net_len - len(udp))
        min_payload = max_payload
    else:
        max_payload = max(0, eth_cfg.payload_max - eth_cfg.net_len - len(udp))
        min_payload = 0

    # 添加随机载荷并更新长度字段
    udp /= str(RandString(size=random.randint(min_payload, max_payload)))
    udp_info.csum_err = False
    return udp_info, udp


def gen_icmpv4(eth_cfg):
    icmpv4_info = Config("icmpv4_info")
    # 随机生成ICMP类型和代码(常见类型：8=请求,0=回复,3=不可达)
    if random.random() < 0.5:
        type = random.randint(0, 255)  # 0-255全范围
    else:
        type = random.choice([0, 3, 5, 8, 11, 12, 13, 14, 15, 16, 17, 18])

    code = random.randint(0, 255)  # 任意代码值
    id = random.randint(0, 65535)  # 随机ID
    seq = random.randint(0, 65535)  # 随机序列号
    gw = random.randint(0, 0xFFFFFFFF) if random.random() > 0.5 else 0  # 50%概率添加网关地址
    ts_ori = random.randint(0, 0xFFFFFFFF) if random.random() > 0.5 else None  # 随机时间戳

    try:
        icmpv4 = ICMP(
            type=type,
            code=code,
            id=id,
            seq=seq,
            gw=gw,
            ts_ori=ts_ori,
        )
    except Exception as e:
        raise ValueError(f"生成ICMPv4失败，参数: type={type}, code={code}, id={id}, seq={seq}, gw={gw}, ts_ori={ts_ori}") from e

    # 计算有效载荷长度
    if eth_cfg.test_mode == "bps":
        max_payload = max(0, eth_cfg.bps_base_len - eth_cfg.net_len - len(icmpv4))
        min_payload = max_payload
    else:
        max_payload = max(0, eth_cfg.payload_max - eth_cfg.net_len - len(icmpv4))
        min_payload = 0

    # 添加随机载荷(如Ping请求/回复的payload)
    icmpv4 /= str(RandString(size=random.randint(min_payload, max_payload)))

    return icmpv4_info, icmpv4


def gen_icmpv6(eth_cfg):
    icmpv6_info = Config("icmpv6_info")
    # 随机生成ICMP类型和代码(常见类型：8=请求,0=回复,3=不可达)
    type = random.randint(0, 255)  # 0-255全范围
    code = random.randint(0, 255)  # 任意代码值
    # type = 136  # 0-255全范围
    # code = 0  # 任意代码值
    # id = random.randint(0, 65535)  # 随机ID
    # seq = random.randint(0, 65535)  # 随机序列号
    # gw = random.randint(0, 0xFFFFFFFF) if random.random() > 0.5 else 0  # 50%概率添加网关地址
    # ts_ori = random.randint(0, 0xFFFFFFFF) if random.random() > 0.5 else None  # 随机时间戳

    try:
        icmpv6 = ICMPv6Unknown(
            type=type,
            code=code,
        )
    except Exception as e:
        raise ValueError(f"生成ICMPv6失败，参数: type={type}, code={code}") from e

    # 计算有效载荷长度
    if eth_cfg.test_mode == "bps":
        max_payload = max(0, eth_cfg.bps_base_len - eth_cfg.net_len - 4)  # 4 = type+code
        min_payload = max(0, eth_cfg.bps_base_len - eth_cfg.net_len - 4)
    else:
        max_payload = max(0, eth_cfg.payload_max - eth_cfg.net_len - 4)
        min_payload = 0

    # 添加随机载荷(如Ping请求/回复的payload)
    icmpv6 /= str(RandString(size=random.randint(min_payload, max_payload)))

    return icmpv6_info, icmpv6


def gen_ipv4_trans(eth_cfg, eth_info, eth_pkt):
    transprot_choices = []

    if eth_cfg.trans_tcp_en:
        transprot_choices.append(('tcp', lambda: gen_tcp(eth_cfg)))
    if eth_cfg.trans_udp_en:
        transprot_choices.append(('udp', lambda: gen_udp(eth_cfg)))
    if eth_cfg.trans_icmpv4_en:
        transprot_choices.append(('icmpv4', lambda: gen_icmpv4(eth_cfg)))

    trans_type, trans_layer = random.choice(transprot_choices)
    trans_info, trans_pkt = trans_layer()
    eth_info.trans_type = trans_type
    eth_info.trans_info = trans_info
    eth_pkt /= trans_pkt
    return eth_cfg, eth_info, eth_pkt


def gen_ipv6_trans(eth_cfg, eth_info, eth_pkt):
    transprot_choices = []

    if eth_cfg.trans_tcp_en:
        transprot_choices.append(('tcp', lambda: gen_tcp(eth_cfg)))
    if eth_cfg.trans_udp_en:
        transprot_choices.append(('udp', lambda: gen_udp(eth_cfg)))
    if eth_cfg.trans_icmpv6_en:
        transprot_choices.append(('icmpv6', lambda: gen_icmpv6(eth_cfg)))

    trans_type, trans_layer = random.choice(transprot_choices)
    trans_info, trans_pkt = trans_layer()
    eth_info.trans_type = trans_type
    eth_info.trans_info = trans_info
    eth_pkt /= trans_pkt
    return eth_cfg, eth_info, eth_pkt


def eth_pkt_build(eth_cfg, eth_info, eth_pkt):
    try:
        _ = eth_pkt.build()
        eth_pkt = Ether(bytes(eth_pkt))  # 强制构建
    except Exception as e:
        raise ValueError(f"数据包构建失败，Ether字段: src={eth_pkt.src}, dst={eth_pkt.dst}, type={eth_pkt.type}") from e

    if IP in eth_pkt:
        eth_info.net_info.ihl = eth_pkt[IP].ihl

        if random.random() < eth_cfg.random_net_csum_err:
            old_chksum = eth_pkt[IP].chksum
            while True:
                new_chksum = random.randint(0, 65535)
                if old_chksum != new_chksum:
                    eth_pkt[IP].chksum = new_chksum
                    break
            eth_info.net_info.csum_err = True

    if TCP in eth_pkt:
        if random.random() < eth_cfg.random_trans_csum_err:
            old_chksum = eth_pkt[TCP].chksum
            while True:
                new_chksum = random.randint(0, 65535)
                if old_chksum != new_chksum:
                    eth_pkt[TCP].chksum = new_chksum
                    break
            eth_info.trans_info.csum_err = True

    if UDP in eth_pkt:
        if random.random() < eth_cfg.random_trans_csum_err:
            old_chksum = eth_pkt[UDP].chksum
            while True:
                new_chksum = random.randint(0, 65535)
                if old_chksum != new_chksum:
                    eth_pkt[UDP].chksum = new_chksum
                    break
            eth_info.trans_info.csum_err = True

        if IP in eth_pkt:
            if random.random() < eth_cfg.random_udp_chksum_zero:
                eth_pkt[UDP].chksum = 0
                eth_info.trans_info.csum_err = False

    return eth_cfg, eth_info, eth_pkt


def generate_eth_pkt(eth_cfg=None, eth_type=None):
    if eth_cfg is None:
        eth_cfg = Eth_Pkg_Cfg("eth_cfg")
    elif not isinstance(eth_cfg, Eth_Pkg_Cfg):
        raise ValueError("参数必须是Eth_Pkg_Cfg实例 或者为 None")

    # 根据eth_type调整bps模式的基础包长度
    if eth_cfg.test_mode == "bps":
        if eth_type == "tx":
            eth_cfg.bps_base_len = 60000  # tx模式bps发包为60k字节
        elif eth_type == "rx":
            eth_cfg.bps_base_len = 1500   # rx模式bps发包为1.5k字节
        else:
            eth_cfg.bps_base_len = 1500   # 默认1.5k字节
    else:
        # 非bps模式使用原有payload_max作为基准
        eth_cfg.bps_base_len = eth_cfg.payload_max

    eth_info = Config("eth_info")
    try:
        eth_pkt = Ether(src=RandMAC(), dst=RandMAC())
    except Exception as e:
        raise ValueError(f"生成Ether失败，参数: src=RandMAC(), dst=RandMAC()") from e

    eth_cfg, eth_info, eth_pkt = gen_vlan(eth_cfg, eth_info, eth_pkt)

    eth_cfg, eth_info, eth_pkt = gen_network(eth_cfg, eth_info, eth_pkt)

    if IP in eth_pkt:
        eth_cfg, eth_info, eth_pkt = gen_ipv4_trans(eth_cfg, eth_info, eth_pkt)
    if IPv6 in eth_pkt:
        eth_cfg, eth_info, eth_pkt = gen_ipv6_trans(eth_cfg, eth_info, eth_pkt)

    eth_cfg, eth_info, eth_pkt = eth_pkt_build(eth_cfg, eth_info, eth_pkt)

    return eth_cfg, eth_info, eth_pkt
