from typing import NamedTuple, TypedDict

# from generate_eth_pkg import Eth_Pkg_Cfg
import logging

CLOCK_FREQ = 5
# DEBUG 调试信息 INFO 一般信息  WARNING 警告信息 ERROR 错误 CRITICAL 严重错误
LOG_LEVEL = logging.DEBUG 
BUS_BYTE_WIDTH = 32


class Err_Type_List(TypedDict):
    no_err: float
    desc_rsp_err: float
    desc_len_err: float
    forced_shutdown: float


err_type_list: Err_Type_List = Err_Type_List(
    no_err=100,
    desc_rsp_err=0,
    desc_len_err=0,
    forced_shutdown=0,
)


class Cfg(NamedTuple):
    pkt_id_num: int
    eth_pkt_len_min: int
    eth_pkt_len_max: int
    q_num: int
    seq_num: int
    alloc_slot_err: float
    min_desc_cnt: int
    max_desc_cnt: int


smoke_cfg = Cfg(
    pkt_id_num=1024,
    eth_pkt_len_min=64,  # 64
    eth_pkt_len_max=1518,  # 1518
    q_num=16,
    seq_num=10000,
    min_desc_cnt=1,
    max_desc_cnt=8,
    alloc_slot_err=0.1,
)
