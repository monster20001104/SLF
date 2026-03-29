from typing import NamedTuple, TypedDict
import logging

CLOCK_FREQ = 5
LOG_LEVEL = logging.DEBUG 
BUS_BYTE_WIDTH = 32


class Err_Type_List(TypedDict):
    no_err: float
    desc_rsp_err: float             
    forced_shutdown: float  
    tlp_err: float
    

err_type_list: Err_Type_List = Err_Type_List(
    no_err=100,            
    desc_rsp_err=0,                   
    forced_shutdown=0, 
    tlp_err=0,     
)


class Cfg(NamedTuple):
    eth_pkt_len_min: int
    eth_pkt_len_max: int
    q_num: int              
    seq_num: int            
    alloc_slot_err: float   
    min_desc_cnt: int       
    max_desc_cnt: int       
    random_qos: float       


smoke_cfg = Cfg(
    eth_pkt_len_min=64,     
    eth_pkt_len_max=1518,   
    q_num=10,                
    seq_num=100,            
    min_desc_cnt=1,
    max_desc_cnt=8,         
    alloc_slot_err=0.0,     
    random_qos=0.8,         
)
